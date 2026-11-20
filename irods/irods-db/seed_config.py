"""Describe development catalog inputs without storing credentials or host paths."""
import hashlib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
RECIPE_FILES = (
    "irods/icat/hooks/bootstrap_irods.sh",
    "irods/ires-hnas/hooks/bootstrap_irods.sh",
    "irods/ires-hnas/hooks/bootstrap_s3_ires.sh",
    "externals/dh-irods/irods-base/config/default_general_json_configuration.json",
    "externals/dh-irods/irods-base/scripts/lib/gen_json_configuration.py",
    "externals/irods-ruleset/datahubirodsruleset/projects/create_new_project.py",
    "externals/irods-ruleset/native_irods_ruleset/policies/acPostProcForCollCreate.r",
)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def describe(compose):
    services = compose["services"]
    if services["icat"]["environment"].get("ENV_ENVIRONMENT") != "dev":
        return None
    versions = {name: services[name]["image"] for name in ("irods-db", "garage1", "garage2")}
    settings = {}
    for name in ("icat", "ires-hnas-um", "ires-hnas-azm"):
        service = services[name]
        versions.update({f"{name}.{key}": value
                         for key, value in service["build"]["args"].items()
                         if key.startswith(("ENV_IRODS_", "ENV_POSTGRES_"))
                         and key.endswith("_VERSION")})
        settings[f"{name}.hostname"] = digest(service["hostname"])
        settings.update({f"{name}.{key}": digest(value)
                         for key, value in service["environment"].items()
                         if key.startswith(("ENV_IRODS_", "ENV_S3_", "ENV_DIRECT_INGEST_"))
                         and key != "ENV_IRODS_WAIT_FOR_CATALOG"})
    settings.update({path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
                     for path in RECIPE_FILES})
    users = {"keycloak/users.json": digest(json.loads((ROOT / "keycloak/users.json").read_text()))}
    users.update({str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in sorted((ROOT / "ldap/ldif_custom").glob("*.ldif"))})
    return {"format": 1, "versions": versions, "users": users, "projects_resources": settings}


def compare(recorded, current):
    if not isinstance(recorded, dict) or recorded.get("format") != current["format"]:
        print("ERROR: Missing or unsupported catalog creation configuration.", file=sys.stderr)
        return 1
    changed = False
    for section in ("versions", "users", "projects_resources"):
        old, new = recorded.get(section, {}), current[section]
        if not isinstance(old, dict):
            old = {}
        if old != new:
            keys = sorted(key for key in old.keys() | new.keys() if old.get(key) != new.get(key))
            print(f"ERROR: Changed {section}: {', '.join(keys)}", file=sys.stderr)
            changed = True
    return int(changed)


if __name__ == "__main__":
    try:
        if sys.argv[1] == "generate":
            config = describe(json.load(sys.stdin))
            if config is not None:
                print(json.dumps(config, sort_keys=True))
        elif sys.argv[1] == "compare":
            sys.exit(compare(json.loads(sys.argv[2]), json.loads(sys.argv[3])))
        else:
            raise ValueError("Unknown configuration command")
    except (ValueError, KeyError, OSError) as error:
        print(f"ERROR: Cannot verify development catalog configuration: {error}", file=sys.stderr)
        sys.exit(1)
