"""Run with python3 -m unittest discover -s keycloak -p 'test_*.py'."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
from threading import Thread
import time
import unittest
from urllib.parse import parse_qs


ROOT = Path(__file__).resolve().parent


class StartupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        self.state = self.work / "state"
        self.requests = []
        self.realm_exists = False
        self.failure_path = ""
        self.sync_failed = 0
        self.http_ready = True
        self.users = [{"username": "auser", "id": "f:ldap-id:auser"},
                      {"username": "buser", "id": "f:ldap-id:buser"}]
        test = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def handle_request(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
                test.requests.append((self.command, self.path, body))
                status, response = 200, {}
                if test.failure_path and test.failure_path in self.path:
                    status = 500
                elif self.path.endswith("/realms/master") and self.command == "GET":
                    status = 200 if test.http_ready else 503
                elif self.path.endswith("/openid-configuration"):
                    status = 200 if test.http_ready else 503
                elif self.path.endswith("/token"):
                    credentials = parse_qs(body)
                    if credentials.get("password") != ["admin password"]:
                        status = 401
                    response = {"access_token": "test-token"}
                elif self.path.endswith("/admin/realms"):
                    if self.command == "GET":
                        response = [{"realm": "django"}] if test.realm_exists else []
                    else:
                        test.realm_exists = True
                        status = 201
                elif "triggerFullSync" in self.path:
                    response = {"failed": test.sync_failed}
                elif "/users?" in self.path:
                    response = test.users if "username=*" in self.path else []
                elif self.command == "PUT":
                    status = 204
                self.send_response(status)
                self.end_headers()
                if status != 204:
                    self.wfile.write(json.dumps(response).encode())

            do_GET = do_POST = do_PUT = handle_request

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.url = f"http://127.0.0.1:{server.server_port}/auth"
        self.users_file = self.work / "users.json"
        self.users_file.write_text(json.dumps([{"userName": "auser"}, {"userName": "buser"}]))
        self.realm_file = self.work / "realm.json"
        self.realm_file.write_text((ROOT / "realm-export.json").read_text())
        self.env = dict(os.environ, KEYCLOAK_USER="admin", KEYCLOAK_PASSWORD="admin password",
                        LDAP_ADMIN_PASSWORD='ldap & " / password', RIT_ENV="test")
        self.env.pop("DEMO_KEYCLOAK_PASSWORD", None)

    def script(self, name):
        return ((ROOT / name).read_text()
                .replace("/var/run/dh_import_state", str(self.state))
                .replace("http://localhost:8080/auth", self.url)
                .replace("/tmp/realm-export.json", str(self.realm_file))
                .replace("/tmp/users.json", str(self.users_file)))

    def run_import(self, script=None):
        return subprocess.run(["bash", "-c", script or self.script("import.sh")],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def password_values(self):
        return [json.loads(body)["value"] for method, path, body in self.requests
                if path.endswith("reset-password")]

    def test_fresh_import_sets_passwords_and_syncs_once(self):
        result = self.run_import()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("completed", self.state.read_text().strip())
        self.assertEqual(["foobar", "foobar"], self.password_values())
        self.assertEqual(1, sum("triggerFullSync" in path for _, path, _ in self.requests))
        self.assertEqual(1, sum("/users?" in path for _, path, _ in self.requests))
        imported = [json.loads(body) for method, path, body in self.requests
                    if method == "POST" and path.endswith("/admin/realms")][0]
        provider = imported["components"]["org.keycloak.storage.UserStorageProvider"][0]
        self.assertEqual([self.env["LDAP_ADMIN_PASSWORD"]], provider["config"]["bindCredential"])
        self.assertTrue(any("f%3Aldap-id%3Aauser" in path for _, path, _ in self.requests))

    def test_existing_realm_is_reused_and_passwords_still_update(self):
        self.realm_exists = True
        self.env["DEMO_KEYCLOAK_PASSWORD"] = 'different & $ " / \\ password\nwith newline'
        result = self.run_import()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([self.env["DEMO_KEYCLOAK_PASSWORD"]] * 2, self.password_values())
        self.assertFalse(any(method == "POST" and path.endswith("/admin/realms")
                             for method, path, _ in self.requests))
        self.assertNotIn(self.env["DEMO_KEYCLOAK_PASSWORD"], result.stdout + result.stderr)

    def test_existing_jenkins_substitution_still_sets_password(self):
        self.env["DEMO_KEYCLOAK_PASSWORD"] = ""
        result = self.run_import(self.script("import.sh").replace("foobar", "jenkins-password"))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["jenkins-password"] * 2, self.password_values())

    def test_environment_override_wins_over_jenkins_default(self):
        self.env["DEMO_KEYCLOAK_PASSWORD"] = "environment-password"
        result = self.run_import(self.script("import.sh").replace("foobar", "jenkins-password"))
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["environment-password"] * 2, self.password_values())

    def test_http_failure_marks_failed(self):
        self.failure_path = "reset-password"
        result = self.run_import()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual("failed", self.state.read_text().strip())

    def test_failed_sync_marks_failed(self):
        self.sync_failed = 1
        result = self.run_import()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual("failed", self.state.read_text().strip())
        self.assertEqual([], self.password_values())

    def test_missing_fixture_user_fails_before_password_updates(self):
        self.users.pop()
        result = self.run_import()
        self.assertNotEqual(0, result.returncode)
        self.assertIn("buser", result.stderr)
        self.assertEqual("failed", self.state.read_text().strip())
        self.assertEqual([], self.password_values())

    def test_http_wait_is_bounded(self):
        self.http_ready = False
        result = self.run_import("sleep() { SECONDS=$((SECONDS + 180)); }\n" + self.script("import.sh"))
        self.assertNotEqual(0, result.returncode)
        self.assertIn("within 180 seconds", result.stderr)
        self.assertEqual("failed", self.state.read_text().strip())

    def test_readiness_requires_completed_import_and_live_http(self):
        for state, http_ready, expected in (("starting", True, 1), ("failed", True, 2),
                                             ("completed", False, 1), ("completed", True, 0)):
            with self.subTest(state=state, http_ready=http_ready):
                self.state.write_text(state)
                self.http_ready = http_ready
                result = subprocess.run(["bash", "-c", self.script("dh_is_ready.sh")],
                                        capture_output=True, text=True)
                self.assertEqual(expected, result.returncode, result.stderr)

    def test_startup_clears_previous_completion_before_background_import(self):
        self.state.write_text("completed")
        importer = self.work / "import.sh"
        checked = self.work / "checked"
        importer.write_text(f'#!/bin/bash\n[[ "$(cat {self.state})" == starting ]] && touch {checked}\n')
        importer.chmod(0o755)
        startup = self.script("startup.sh").replace("/tmp/import.sh", str(importer))
        result = subprocess.run(["bash", "-c", startup], capture_output=True, text=True, timeout=5)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertTrue(checked.exists())


class WaitTests(unittest.TestCase):
    def test_wait_handles_success_failure_exited_container_and_timeout(self):
        rit = (ROOT.parent / "rit.sh").read_text()
        helper = rit[rit.index("wait_for_keycloak(){"):rit.index("\nrun_minimal(){")]
        for mode, expected in (("ready", 0), ("failed", 1), ("exited", 1), ("timeout", 1)):
            with self.subTest(mode=mode):
                result = subprocess.run(["bash", "-c", '''
set -euo pipefail
timeout() { while [[ "$1" == --* ]]; do shift; done; shift; "$@"; }
sleep() { SECONDS=$((SECONDS + 150)); }
docker() {
  if [[ "$*" == *dh_is_ready.sh* ]]; then
    case "$MODE" in ready) return 0;; failed) return 2;; *) return 1;; esac
  elif [[ "$*" == *"ps -a"* ]]; then
    if [[ "$MODE" == exited ]]; then echo exited; else echo running; fi
  fi
}
''' + helper + "\nwait_for_keycloak\n"], env=dict(os.environ, MODE=mode),
                                        capture_output=True, text=True, timeout=5)
                self.assertEqual(expected, result.returncode, result.stderr)

    def run_with_blocking_docker(self, mode, interrupt=False):
        rit = (ROOT.parent / "rit.sh").read_text()
        script = rit[rit.index("set -e\n"):rit.index("\nrun_minimal(){")]
        script = script.replace("2s", "0.1s").replace("5s", "0.2s")
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            docker = work / "docker"
            docker.write_text("""#!/usr/bin/env python3
import os, signal, sys, time
from pathlib import Path
mode = os.environ['MODE']
probe = '/dh_is_ready.sh' in sys.argv
if probe and mode == 'stdin':
    assert '--interactive=false' in sys.argv
    assert sys.stdin.read(1) == ''
    sys.exit(0)
if (probe and mode in ('probe', 'interrupt')) or (not probe and mode == 'status'):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    Path(os.environ['STARTED']).touch()
    while True:
        time.sleep(1)
if probe:
    sys.exit(1)
print('exited')
""")
            docker.chmod(0o755)
            env = dict(os.environ, PATH=f"{work}:{os.environ['PATH']}", MODE=mode,
                       STARTED=str(work / "started"))
            process = subprocess.Popen(
                ["bash", "-c", script + '\nsleep() { SECONDS=$((SECONDS + 300)); }\nwait_for_keycloak\n'],
                env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True, start_new_session=True)
            try:
                if interrupt:
                    deadline = time.monotonic() + 3
                    while not (work / "started").exists() and time.monotonic() < deadline:
                        time.sleep(0.01)
                    self.assertTrue((work / "started").exists())
                    os.killpg(process.pid, signal.SIGINT)
                # Keep stdin open to reproduce a Docker client waiting for terminal input.
                process.wait(timeout=3)
                stdout, stderr = process.communicate()
                return process.returncode, stdout, stderr
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                process.communicate()

    def test_probe_does_not_read_callers_stdin(self):
        status, stdout, stderr = self.run_with_blocking_docker("stdin")
        self.assertEqual(0, status, stderr)
        self.assertIn("Waiting for Keycloak", stdout)

    def test_unresponsive_probe_status_and_logs_have_hard_timeouts(self):
        for mode in ("probe", "status"):
            with self.subTest(mode=mode):
                status, _, stderr = self.run_with_blocking_docker(mode)
                self.assertEqual(1, status, stderr)
                self.assertIn("Keycloak initialization failed", stderr)

    def test_ctrl_c_exits_even_when_docker_ignores_signals(self):
        status, _, stderr = self.run_with_blocking_docker("interrupt", interrupt=True)
        self.assertEqual(130, status, stderr)


if __name__ == "__main__":
    unittest.main()
