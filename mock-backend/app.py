"""Deterministic iRODS fixtures for MDR. No database and no writable backend state."""
import base64
import json
import re
from pathlib import Path, PurePosixPath

from flask import Flask, jsonify, request

ROOT = Path(__file__).parent
FIXTURES = ROOT / "fixtures"
DATA = json.loads((FIXTURES / "responses.json").read_text())
MANIFEST = json.loads((ROOT / "operations.json").read_text())
app = Flask(__name__)


class FixtureError(Exception):
    def __init__(self, message, kind="MockBackendError", status=404):
        self.message, self.kind, self.status = message, kind, status


@app.errorhandler(FixtureError)
def fixture_error(error):
    return jsonify(error={"type": error.kind, "message": error.message}), error.status


def identity(payload):
    user = "admin" if payload.get("admin_mode") else payload.get("client_user")
    if user not in DATA["identities"]:
        raise FixtureError(f"Unknown mock user: {user}", "CAT_INVALID_CLIENT_USER", 403)
    return user


def rule_name(name):
    if name.startswith("IRULE_") and MANIFEST["rules"].get(name[6:], {}).get("native"):
        return name[6:]
    return name


def select(name, arguments, user):
    rows = DATA["rules"][name]
    write = MANIFEST["rules"][name].get("write", False)
    matching = [row for row in rows if all(arguments.get(k) == v for k, v in row["match"].items())]
    matches = [row for row in matching if write or user in row["users"]]
    if not matches:
        if matching:
            raise FixtureError("Fixture is not visible to this user", "CAT_NO_ACCESS_PERMISSION", 403)
        raise FixtureError(f"No fixture for {user}/{name}: {arguments}")
    row = max(matches, key=lambda row: len(row["match"]))
    if "error" in row:
        raise FixtureError(row["error"], row.get("error_type", "CAT_NO_ACCESS_PERMISSION"), 403)
    if "result_files" in row:
        return {key: json.loads((FIXTURES / filename).read_text())
                for key, filename in row["result_files"].items()}
    return row["result"]


def decode_params(params):
    # format_rule_argument quotes strings with the native rule-language syntax.
    # Match that syntax without evaluating rule code or arbitrary expressions.
    result = {}
    for key, value in params.items():
        if isinstance(value, str) and len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]:
            value = value[1:-1].replace("\\" + value[0], value[0]).replace("\\\\", "\\")
        result[key] = value
    return result


@app.get("/health")
def health():
    return jsonify(status="ok", mode="static-mock")


@app.post("/rules/<name>")
def rule(name):
    payload = request.get_json()
    user = identity(payload)
    name = rule_name(name)
    if name not in MANIFEST["rules"]:
        raise FixtureError(f"Unsupported rule: {name}")
    arguments = decode_params(payload.get("arguments", {}))
    return jsonify(select(name, arguments, user))


def check_path(path, user):
    if not isinstance(path, str) or not path.startswith("/nlmumc/") or ".." in PurePosixPath(path).parts:
        raise FixtureError(f"Invalid fixture path: {path}", status=400)
    projects = re.findall(r"P[0-9]{9}", path)
    if any(project not in DATA["identities"][user]["projects"] for project in projects):
        raise FixtureError("Project is not visible to this user", "CAT_NO_ACCESS_PERMISSION", 403)
    return path.rstrip("/")


def file_bytes(path):
    entry = DATA["files"].get(path)
    if entry is None:
        raise FixtureError(f"No file fixture: {path}", "DataObjectDoesNotExist")
    return (FIXTURES / entry["fixture"]).read_bytes()


def file_info(path, content):
    return {"id": 20001, "name": PurePosixPath(path).name, "path": path,
            "size": len(content), "resource_name": DATA["files"].get(path, {}).get("resource_name", "passRescUM01"),
            "create_time": "2026-01-01T12:00:00+00:00", "modify_time": "2026-01-01T12:00:00+00:00"}


@app.post("/api/<operation>")
def api(operation):
    payload = request.get_json()
    user = identity(payload)
    args = payload.get("arguments", {})
    if operation not in MANIFEST["api"]:
        raise FixtureError(f"Unsupported API operation: {operation}")
    if operation == "check_connection":
        return jsonify(True)
    if operation.startswith("users."):
        name = args["name"]
        if name not in DATA["users"]:
            raise FixtureError(f"Unknown user: {name}", "CAT_INVALID_CLIENT_USER", 403)
        return jsonify(DATA["users"][name] if operation == "users.get" else "mock-password")
    if operation == "specific_query":
        if str(args["args"][0]) not in {str(u["id"]) for u in DATA["users"].values()}:
            raise FixtureError("Unknown user ID", "CAT_INVALID_CLIENT_USER", 403)
        results = {"count_password": 1, "delete_password": None, "get_create_ts_password": 1893456000}
        if args["alias"] not in results:
            raise FixtureError(f"Unsupported query: {args['alias']}")
        return jsonify(results[args["alias"]])
    path = check_path(args.get("path", args.get("source")), user)
    if "destination" in args:
        check_path(args["destination"], user)
    if operation == "collections.exists":
        return jsonify(path in DATA["directories"])
    if operation == "data_objects.exists":
        return jsonify(path in DATA["files"])
    if operation == "data_objects.get":
        # File-manager upload completion stats are fixed even for discarded files.
        if path not in DATA["files"] and not path.startswith("/nlmumc/ingest/direct/"):
            file_bytes(path)
        content = file_bytes(path) if path in DATA["files"] else b""
        return jsonify(file_info(path, content))
    if operation == "data_objects.open":
        if args["mode"] in ("r", "r+"):
            return jsonify(content=base64.b64encode(file_bytes(path)).decode())
        if args["mode"] not in ("w", "w+", "a", "a+"):
            raise FixtureError("Unsupported file mode", status=400)
    # Every operation reaching here is explicitly listed as a discarded write.
    return jsonify(None)


@app.post("/integrations/search")
def search():
    payload = request.get_json()
    user = identity(payload)
    term = payload.get("search", "").lower()
    hits = DATA["search"]
    if payload.get("access_filter"):
        hits = [hit for hit in hits if hit["_source"]["project_id"] in DATA["identities"][user]["projects"]]
    return jsonify([hit for hit in hits if term in json.dumps(hit["_source"]).lower()])


@app.post("/integrations/jira/<action>")
def jira(action):
    if action not in ("create", "comment"):
        raise FixtureError("Unsupported Jira action")
    return jsonify("MOCK-1" if action == "create" else None)


@app.post("/help_backend/submit_request/<action>")
def help_request(action):
    if action not in ("irods_uuid", "data_deletion_request"):
        raise FixtureError("Unsupported help-center action")
    return jsonify(success=True, key="MOCK-1")


@app.get("/search")
def bioportal():
    return jsonify(DATA["bioportal"])


@app.get("/help_backend/confluence_documents/excerpts/label/<label>")
def help_excerpts(label):
    return jsonify(json.loads((FIXTURES / "help.json").read_text())["excerpts"])


@app.get("/help_backend/confluence_documents/id/<document_id>")
def help_document(document_id):
    if document_id != "mock-help":
        raise FixtureError("Unknown help document")
    return jsonify(json.loads((FIXTURES / "help.json").read_text())["document"])


@app.get("/quickstart")
@app.get("/access")
@app.get("/store")
@app.get("/manage")
@app.get("/support")
@app.get("/support/<int:user_id>")
@app.get("/page_id/<document_id>")
@app.get("/")
def help_page(user_id=None, document_id=None):
    return "<h1>MDR mock environment</h1><p>Service actions return fixed success responses. Changes are discarded.</p>"
