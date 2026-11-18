"""Read-only capture: docker exec -i dev-mdr-1 python < mock-backend/capture.py > capture.json.

Only the explicit calls below execute. Rule output is recorded before DTO parsing.
The output contains development fixture data, never connection configuration.
"""
import json
import re
import sys
from irods.rule import Rule
from irodsrulewrapper.rule import RuleManager

records = []
original_execute = Rule.execute
identity = None


def record_execute(rule, *args, **kwargs):
    result = original_execute(rule, *args, **kwargs)
    raw = result.MsParam_PI[0].inOutStruct.stdoutBuf.buf.rstrip(b"\0").decode("utf-8")
    name = re.search(r'\*result="";\s*(\w+)\(', rule.body).group(1)
    records.append({"user": identity, "rule": name, "params": rule.params,
                    "result": json.loads(raw) if raw.strip() else None})
    return result


Rule.execute = record_execute


def call(manager, method, *args):
    try:
        return getattr(manager, method)(*args)
    except Exception as error:
        print(f"Skipped {identity}/{method}: {type(error).__name__}: {error}", file=sys.stderr)


for identity in ("admin", "dlinssen", "minimalist"):
    manager = RuleManager(admin_mode=True) if identity == "admin" else RuleManager(identity)
    for method, args in [
        ("get_users", ("false",)), ("get_groups", ("false",)),
        ("get_data_stewards", ()), ("get_ingest_resources", ()),
        ("get_destination_resources", ()), ("get_projects_overview", ()),
        ("get_projects_minimal", ()), ("get_contributing_projects", ("false",)),
        ("get_projects_finance", ()), ("get_user_active_processes", ("true", "true", "true")),
        ("get_temporary_password_lifetime", ()),
    ]:
        call(manager, method, *args)
    for username in ("dlinssen", "minimalist"):
        call(manager, "get_user_group_memberships", "true", username)
        call(manager, "get_user_internal_affiliation_status", username)
        for attribute in ("lastToSAcceptedTimestamp", "displayName", "email"):
            call(manager, "get_user_attribute_value", username, attribute, "false")
    for project in ("P000000001", "P000000002"):
        path = "/nlmumc/projects/" + project
        for method, args in [
            ("get_project_details", (path, "false")),
            ("get_project_acl_for_manager", (project, "false")),
            ("get_contributing_project", (project, "false")),
            ("get_project_contributors", (project, "true", "false")),
            ("get_project_contributors_metadata", (project,)),
            ("get_project_process_activity", (project,)),
            ("get_project_resource_availability", (project, "true", "true", "true")),
            ("get_collections", (path,)), ("get_collection_size_per_resource", (project,)),
        ]:
            call(manager, method, *args)
        for collection in ("C000000001",):
            cp = path + "/" + collection
            call(manager, "get_project_collection_details", project, collection, "true")
            call(manager, "get_project_collection_process_activity", cp)
            call(manager, "check_edit_metadata_permission", cp)
            call(manager, "get_collection_tree", project + "/" + collection)
            for attribute in ("latest_version_number", "title", "accessRestriction", "dataDeletionState",
                              "enableArchive", "enableUnarchive", "schemaName", "schemaVersion"):
                call(manager, "get_collection_attribute_value", cp, attribute)
            for kind in ("schema", "instance"):
                try:
                    value = getattr(manager, f"read_{kind}_from_collection")(project, collection)
                    records.append({"user": identity, "file": cp + "/" + kind + ".json", "result": value})
                except Exception as error:
                    print(f"Skipped {cp}/{kind}: {type(error).__name__}", file=sys.stderr)
    manager.cleanup()

# UID expansion is performed under this service identity by existing DTO factories.
identity = "service-disqover"
manager = RuleManager(identity)
for uid in ("10044", "10074"):
    call(manager, "get_user_or_group_by_id", uid)
manager.cleanup()
json.dump(records, sys.stdout, indent=2)
print()
