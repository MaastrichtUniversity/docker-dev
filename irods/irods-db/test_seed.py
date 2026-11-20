"""Run with python3 -m unittest discover -s irods/irods-db -p 'test_*.py'."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from seed_config import RECIPE_FILES


ROOT = Path(__file__).resolve().parents[2]


class SeedTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.seed = self.root / "irods/irods-db/seed"
        self.seed.mkdir(parents=True)
        shutil.copy(ROOT / "irods/irods-db/seed.sh", self.seed.parent)
        shutil.copy(ROOT / "irods/irods-db/seed_config.py", self.seed.parent)
        shutil.copy(ROOT / "rit.sh", self.root)
        for filename in RECIPE_FILES:
            path = self.root / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture recipe\n")
        (self.root / "keycloak").mkdir()
        (self.root / "keycloak/users.json").write_text('[{"userName": "alice"}]')
        (self.root / "ldap/ldif_custom").mkdir(parents=True)
        (self.root / "ldap/ldif_custom/99_users.ldif").write_text("fixture LDAP users\n")
        self.compose_file = self.root / "compose.json"
        services = {name: {"image": f"{name}:1", "hostname": name,
                           "build": {"args": {"ENV_IRODS_VERSION": "5.1.0"}},
                           "environment": {"ENV_ENVIRONMENT": "dev", "ENV_IRODS_COOR_RESC_NAME": "test-resource"}}
                    for name in ("icat", "ires-hnas-um", "ires-hnas-azm", "irods-db", "garage1", "garage2")}
        self.compose_file.write_text(json.dumps({"services": services}))
        (self.root / ".env").write_text("fixture configuration\n")
        (self.root / "irods.secrets.cfg").write_text("")
        (self.root / "lib-dh.sh").write_text("env_selector() { :; }\nlog() { :; }\nDBG=4\n")
        self.state = self.root / "tables"
        self.state.write_text("0")
        self.markers = self.root / "pgdata"
        self.markers.mkdir()
        self.exists = self.root / "database-exists"
        self.log = self.root / "docker.jsonl"
        mock_bin = self.root / "bin"
        mock_bin.mkdir()
        docker = mock_bin / "docker"
        docker.write_text("""#!/usr/bin/env python3
import io, json, os, pathlib, sys, tarfile
args = sys.argv[1:]
with open(os.environ['DOCKER_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
state = pathlib.Path(os.environ['CATALOG_STATE'])
markers = pathlib.Path(os.environ['CATALOG_MARKERS'])
exists = pathlib.Path(os.environ['DATABASE_EXISTS'])
if 'rm' in args and 'irods-db' in args:
    state.write_text('0')
    exists.unlink(missing_ok=True)
    for path in markers.iterdir():
        path.unlink()
elif args[:2] == ['network', 'ls']:
    print('true')
elif 'config' in args:
    print(pathlib.Path(os.environ['COMPOSE_CONFIG']).read_text())
elif args[0] == 'inspect':
    print('PGDATA=/var/lib/postgresql/data')
elif args[0] == 'cp':
    name = pathlib.Path(args[1]).name
    path = markers / name
    if not path.exists():
        sys.exit(1)
    data = path.read_bytes()
    with tarfile.open(fileobj=sys.stdout.buffer, mode='w|') as archive:
        info = tarfile.TarInfo(name)
        info.size = len(data)
        archive.addfile(info, io.BytesIO(data))
elif 'up' in args and 'irods-db' in args:
    exists.touch()
elif 'exec' in args:
    command = ' '.join(args)
    if '/var/run/irods_catalog_ready' in args and os.environ.get('RELEASE_FAIL'):
        sys.exit(1)
    if 'cat > "$PGDATA/' in command:
        (markers / args[-1]).write_bytes(sys.stdin.buffer.read())
    elif 'mv "$PGDATA/dh-dev-config.pending.json"' in command:
        (markers / 'dh-dev-config.pending.json').replace(markers / 'dh-dev-config.json')
    elif 'pg_restore' in command:
        sys.stdin.buffer.read()
        if os.environ.get('RESTORE_FAIL'):
            sys.exit(1)
        state.write_text('30')
    elif 'SELECT count(*) FROM pg_tables' in command:
        print(state.read_text())
    elif 'SELECT 1' in command:
        print('1')
    elif 'r_coll_main' in command:
        print('t')
elif 'ps' in args:
    if '-q' in args:
        if exists.exists():
            print('test-db')
    else:
        print('running')
""")
        docker.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{mock_bin}:{os.environ['PATH']}",
                        DOCKER_LOG=str(self.log), CATALOG_STATE=str(self.state),
                        CATALOG_MARKERS=str(self.markers), DATABASE_EXISTS=str(self.exists),
                        COMPOSE_CONFIG=str(self.compose_file),
                        DH_ENV_HOME=str(self.root), RIT_ENV="local")

    def run_seed(self, mode):
        return subprocess.run(["bash", "irods/irods-db/seed.sh", "prepare", mode],
                              cwd=self.root, env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def make_seed(self):
        dump = self.seed / "icat.dump"
        dump.write_bytes(b"test catalog archive")
        digest = hashlib.sha256(dump.read_bytes()).hexdigest()
        (self.seed / "icat.dump.sha256").write_text(f"{digest}  icat.dump\n")
        (self.seed / "config.json").write_text(self.current_config())

    def current_config(self):
        return subprocess.check_output(["python3", "irods/irods-db/seed_config.py", "generate"],
                                       cwd=self.root, input=self.compose_file.read_text(), text=True)

    def existing_catalog(self, pending=False):
        self.state.write_text("30")
        self.exists.touch()
        name = "dh-dev-config.pending.json" if pending else "dh-dev-config.json"
        (self.markers / name).write_text(self.current_config())

    def change_service(self, service, section, key, value):
        config = json.loads(self.compose_file.read_text())
        config["services"][service][section][key] = value
        self.compose_file.write_text(json.dumps(config))

    def assert_no_restore_or_delete(self):
        commands = self.calls()
        self.assertFalse(any("pg_restore" in " ".join(args) for args in commands))
        self.assertFalse(any("rm" in args or "stop" in args for args in commands))

    def assert_no_start_or_delete(self):
        self.assert_no_restore_or_delete()
        self.assertFalse(any("up" in args for args in self.calls()))

    def test_existing_catalog_without_creation_record_is_refused_before_start(self):
        self.exists.touch()
        self.state.write_text("30")
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no recorded creation configuration", result.stderr)
        self.assert_no_start_or_delete()

    def test_existing_catalog_version_change_is_refused_before_start(self):
        self.existing_catalog()
        self.change_service("icat", "build", "args", {"ENV_IRODS_VERSION": "5.2.0"})
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed versions", result.stderr)
        self.assert_no_start_or_delete()

    def test_postgres_image_change_is_refused_before_start(self):
        self.existing_catalog()
        config = json.loads(self.compose_file.read_text())
        config["services"]["irods-db"]["image"] = "postgres:18"
        self.compose_file.write_text(json.dumps(config))
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed versions: irods-db", result.stderr)
        self.assert_no_start_or_delete()

    def test_changed_users_are_refused_before_start(self):
        self.existing_catalog()
        (self.root / "keycloak/users.json").write_text('[{"userName": "bob"}]')
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed users", result.stderr)
        self.assert_no_start_or_delete()

    def test_changed_ldap_fixtures_are_refused_before_start(self):
        self.existing_catalog()
        (self.root / "ldap/ldif_custom/99_users.ldif").write_text("changed LDAP users\n")
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed users", result.stderr)
        self.assert_no_start_or_delete()

    def test_resource_configuration_change_is_refused_before_start(self):
        self.existing_catalog()
        self.change_service("ires-hnas-um", "environment", "ENV_IRODS_COOR_RESC_NAME", "other-resource")
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed projects_resources", result.stderr)
        self.assert_no_start_or_delete()

    def test_project_recipe_change_is_refused_before_start(self):
        self.existing_catalog()
        (self.root / "irods/ires-hnas/hooks/bootstrap_irods.sh").write_text("different projects\n")
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed projects_resources", result.stderr)
        self.assert_no_start_or_delete()

    def test_incomplete_catalog_is_not_accepted(self):
        self.existing_catalog(pending=True)
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("initialization did not finish", result.stderr)
        self.assert_no_restore_or_delete()

    def test_incomplete_record_takes_precedence_over_old_completed_record(self):
        self.existing_catalog()
        self.existing_catalog(pending=True)
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("initialization did not finish", result.stderr)

    def test_unrelated_environment_file_change_does_not_require_reset(self):
        self.existing_catalog()
        (self.root / ".env").write_text("# Different comments or unrelated app settings\n")
        result = self.run_seed("snapshot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_no_restore_or_delete()

    def test_startup_gate_setting_does_not_change_creation_config(self):
        self.existing_catalog()
        self.change_service("ires-hnas-um", "environment", "ENV_IRODS_WAIT_FOR_CATALOG", "true")
        result = self.run_seed("snapshot")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_checks_are_disabled_outside_development(self):
        self.exists.touch()
        self.state.write_text("30")
        for environment in ("acc", "prod"):
            with self.subTest(environment=environment):
                self.change_service("icat", "environment", "ENV_ENVIRONMENT", environment)
                result = self.run_seed("snapshot")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("disabled outside dev", result.stdout)
        self.assertFalse(any(args[0] in ("cp", "inspect") for args in self.calls()))
        self.assertEqual(list(self.markers.iterdir()), [])

    def test_failed_fresh_bootstrap_is_not_marked_complete(self):
        result = self.run_seed("fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.markers / "dh-dev-config.pending.json").exists())
        self.assertFalse((self.markers / "dh-dev-config.json").exists())

    def test_complete_promotes_fresh_record_and_allows_reuse(self):
        self.assertEqual(self.run_seed("fresh").returncode, 0)
        self.state.write_text("30")
        result = subprocess.run(["bash", "irods/irods-db/seed.sh", "complete"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.markers / "dh-dev-config.json").exists())
        self.assertFalse((self.markers / "dh-dev-config.pending.json").exists())
        self.assertEqual(self.run_seed("snapshot").returncode, 0)

    def test_change_during_fresh_bootstrap_cannot_be_marked_complete(self):
        self.assertEqual(self.run_seed("fresh").returncode, 0)
        (self.root / "keycloak/users.json").write_text('[{"userName": "bob"}]')
        result = subprocess.run(["bash", "irods/irods-db/seed.sh", "complete"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.markers / "dh-dev-config.pending.json").exists())
        self.assertFalse((self.markers / "dh-dev-config.json").exists())

    def test_reset_with_stale_seed_is_refused_before_deletion(self):
        self.make_seed()
        self.existing_catalog()
        self.change_service("icat", "build", "args", {"ENV_IRODS_VERSION": "5.2.0"})
        result = subprocess.run(["bash", "rit.sh", "backend", "--reset"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_start_or_delete()

    def test_creation_record_does_not_expose_credentials(self):
        self.change_service("icat", "environment", "ENV_IRODS_PASSWORD_ADMIN", "private-test-password")
        config = self.current_config()
        self.assertNotIn("private-test-password", config)
        self.assertIn("ENV_IRODS_PASSWORD_ADMIN", config)

    def test_fresh_empty_catalog_bypasses_seed(self):
        result = self.run_seed("fresh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("normal bootstrap scripts", result.stdout)
        self.assert_no_restore_or_delete()

    def test_fresh_populated_catalog_is_refused(self):
        self.existing_catalog()
        result = self.run_seed("fresh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--reset --fresh", result.stderr)
        self.assertEqual(self.state.read_text(), "30")
        self.assert_no_restore_or_delete()

    def test_existing_catalog_does_not_require_a_seed(self):
        self.existing_catalog()
        result = self.run_seed("snapshot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("existing iRODS catalog", result.stdout)
        self.assert_no_restore_or_delete()

    def test_missing_seed_is_refused_without_populating_catalog(self):
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("seed rebuild", result.stderr)
        self.assert_no_restore_or_delete()

    def test_valid_seed_restores_in_one_transaction(self):
        self.make_seed()
        result = self.run_seed("snapshot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.state.read_text(), "30")
        restore = [args for args in self.calls() if "pg_restore" in " ".join(args)]
        self.assertEqual(len(restore), 1)
        self.assertIn("--single-transaction", " ".join(restore[0]))

    def test_changed_configuration_is_refused(self):
        self.make_seed()
        self.change_service("icat", "build", "args", {"ENV_IRODS_VERSION": "5.2.0"})
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Changed versions", result.stderr)
        self.assert_no_restore_or_delete()

    def test_corrupt_archive_is_refused(self):
        self.make_seed()
        (self.seed / "icat.dump").write_bytes(b"truncated")
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assert_no_restore_or_delete()

    def test_restore_failure_is_reported(self):
        self.make_seed()
        self.env["RESTORE_FAIL"] = "1"
        result = self.run_seed("snapshot")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text(), "0")

    def test_backend_forwards_fresh_and_stops_on_populated_catalog(self):
        self.existing_catalog()
        result = subprocess.run(["bash", "rit.sh", "backend", "--fresh"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--reset --fresh", result.stderr)
        self.assert_no_restore_or_delete()
        self.assertFalse(any("backend" in args for args in self.calls()))

    def test_unknown_backend_option_is_rejected_before_startup(self):
        result = subprocess.run(["bash", "rit.sh", "backend", "--frehs"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown backend option", result.stderr)
        self.assertFalse(any("up" in args for args in self.calls()))

    def test_backend_fresh_continues_through_normal_startup(self):
        result = subprocess.run(["bash", "rit.sh", "backend", "--fresh"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any("backend-after-icat" in args for args in self.calls()))
        calls = self.calls()
        early_resources = next(i for i, args in enumerate(calls)
                               if "up" in args and "ires-hnas-um" in args)
        provider = next(i for i, args in enumerate(calls) if "backend" in args)
        self.assertLess(early_resources, provider)
        releases = [i for i, args in enumerate(calls) if "/var/run/irods_catalog_ready" in args]
        self.assertEqual(len(releases), 2)
        self.assertTrue(all(i > provider for i in releases))
        self.assertFalse(any("pg_restore" in " ".join(args) for args in self.calls()))
        self.assertFalse(any("rm" in args for args in self.calls()))
        stops = [args for args in self.calls() if "stop" in args]
        self.assertEqual(stops[0][-1], "sram-sync")

    def test_reset_is_explicit_and_scoped_to_irods(self):
        self.state.write_text("30")
        result = subprocess.run(["bash", "rit.sh", "backend", "--reset", "--fresh"],
                                cwd=self.root, env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        removal = [args for args in self.calls() if "rm" in args]
        self.assertEqual(len(removal), 1)
        self.assertIn("irods-db", removal[0])
        self.assertIn("-v", removal[0])
        self.assertNotIn("mdr-db", removal[0])
        self.assertNotIn("keycloak", removal[0])
        self.assertNotIn("elastic", removal[0])
        self.assertEqual(self.state.read_text(), "0")

    def test_failed_resource_release_stops_backend_startup(self):
        self.env["RELEASE_FAIL"] = "1"
        result = subprocess.run(["bash", "rit.sh", "backend", "--fresh"],
                                cwd=self.root, env=self.env, capture_output=True, text=True,
                                timeout=10)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not release ires-hnas-um startup", result.stderr)
        self.assertFalse(any("backend-after-icat" in args for args in self.calls()))
        self.assertTrue((self.markers / "dh-dev-config.pending.json").exists())
        self.assertFalse((self.markers / "dh-dev-config.json").exists())


class ConsumerHookTests(unittest.TestCase):
    def run_hook(self, bootstrap_status=0, never_ready=False):
        script = (ROOT / "irods/ires-hnas/hooks/bootstrap_post_hook.sh").read_text()
        prefix = """
probes=0
timeout() { shift; "$@"; }
sleep() { SECONDS=$((SECONDS + 60)); }
su() {
    if [[ "$*" == *'ils /nlmumc/projects'* ]]; then
        ((probes+=1))
        [[ "$NEVER_READY" == no && $probes -ge 2 ]]
    else
        echo "$*" >> "$HOOK_CALLS"
        return "$BOOTSTRAP_STATUS"
    fi
}
"""
        with tempfile.TemporaryDirectory() as directory:
            calls = Path(directory) / "calls"
            env = dict(os.environ, HOOK_CALLS=str(calls), NEVER_READY="yes" if never_ready else "no",
                       BOOTSTRAP_STATUS=str(bootstrap_status),
                       ENV_IRODS_COOR_RESC_NAME="passRescUM01",
                       ENV_S3_RESC_NAME_AC="ac", ENV_S3_HOST_AC="ac", ENV_S3_AUTH_FILE_AC="ac",
                       ENV_S3_RESC_NAME_GL="gl", ENV_S3_HOST_GL="gl", ENV_S3_AUTH_FILE_GL="gl")
            result = subprocess.run(["bash", "-c", prefix + script], env=env,
                                    capture_output=True, text=True)
            return result, calls.read_text().splitlines() if calls.exists() else []

    def test_waits_for_local_server_before_running_both_bootstraps(self):
        result, calls = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Waiting for the local iRODS server", result.stdout)
        self.assertEqual(len(calls), 2)

    def test_bootstrap_failure_stops_before_s3_bootstrap(self):
        result, calls = self.run_hook(bootstrap_status=7)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(len(calls), 1)

    def test_local_readiness_timeout_skips_bootstrap(self):
        result, calls = self.run_hook(never_ready=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not become ready", result.stderr)
        self.assertEqual(calls, [])


class CatalogGateTests(unittest.TestCase):
    def run_gate(self, enabled, never_ready=False):
        script = (ROOT / "irods/ires-hnas/hooks/wait_for_catalog.sh").read_text()
        script = script.replace("/var/run/irods_catalog_ready", '"$READY_FILE"')
        script = script.replace("exec /opt/irods/init.sh", "exec bash -c 'echo INITIALIZED'")
        prefix = """
sleep() {
    if [[ "$NEVER_READY" == yes ]]; then
        SECONDS=$((SECONDS + 600))
    else
        touch "$READY_FILE"
    fi
}
"""
        with tempfile.TemporaryDirectory() as directory:
            env = dict(os.environ, READY_FILE=f"{directory}/ready",
                       ENV_IRODS_WAIT_FOR_CATALOG="true" if enabled else "false",
                       NEVER_READY="yes" if never_ready else "no")
            return subprocess.run(["bash", "-c", prefix + script], env=env,
                                  capture_output=True, text=True)

    def test_direct_compose_start_does_not_wait_for_host_release(self):
        result = self.run_gate(enabled=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "INITIALIZED")

    def test_backend_gate_waits_for_release_then_initializes(self):
        result = self.run_gate(enabled=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Waiting for rit.sh", result.stdout)
        self.assertIn("INITIALIZED", result.stdout)

    def test_backend_gate_timeout_does_not_initialize(self):
        result = self.run_gate(enabled=True, never_ready=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("INITIALIZED", result.stdout)
        self.assertIn("Timed out", result.stderr)


if __name__ == "__main__":
    unittest.main()
