"""Run in mock MDR after copying this directory to /tmp/mdr-mock-tests."""
import ast
import importlib
import json
import os
from pathlib import Path
import unittest

from irods.exception import OBJ_PATH_DOES_NOT_EXIST, SYS_NOT_SUPPORTED
from irods.rule import Rule
from irods.session import iRODSSession
from irodsrulewrapper.rule import RuleManager, RuleJSONManager
from irodsrulewrapper.session_pool import IRODSSessionPool
from irodsrulewrapper.utils import irods_session_scope

ROOT = Path(__file__).parent
DATA = json.loads((ROOT / "fixtures/responses.json").read_text())
MANIFEST = json.loads((ROOT / "operations.json").read_text())
PID = "P000000001"
CID = "C000000001"
CP = f"/nlmumc/projects/{PID}/{CID}"


class WrapperTests(unittest.TestCase):
    def setUp(self):
        if os.environ.get("IRODS_HOST") != "mock-backend":
            self.skipTest("Requires a mock stack")
        self.manager = RuleManager("dlinssen")

    def test_all_fixture_dto_factories(self):
        for name, contract in MANIFEST["rules"].items():
            if contract["dto"] == "None":
                continue
            module = importlib.import_module("irodsrulewrapper.rule_managers." + Path(contract["file"]).stem)
            factory = getattr(module, contract["dto"])
            for row in DATA["rules"][name]:
                if "error" in row:
                    continue
                with self.subTest(rule=name, match=row["match"]):
                    factory.create_from_rule_result(row["result"])

    def test_manifest_tracks_all_wrapper_rules(self):
        import irodsrulewrapper
        names = set()
        for source in (Path(irodsrulewrapper.__file__).parent / "rule_managers").glob("*.py"):
            for node in ast.walk(ast.parse(source.read_text())):
                if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "RuleInfo":
                    names.add(next(ast.literal_eval(k.value) for k in node.keywords if k.arg == "name"))
        self.assertEqual(names, set(MANIFEST["rules"]))

    def test_native_pool_reuses_mock_connection(self):
        pool = IRODSSessionPool()
        self.addCleanup(pool.close)
        with irods_session_scope(pool=pool):
            first = RuleManager("dlinssen").session
            self.assertIs(type(first), iRODSSession)
        with irods_session_scope(pool=pool):
            manager = RuleManager("dlinssen")
            self.assertIs(manager.session, first)
            self.assertTrue(manager.check_irods_connection())

    def test_identity_and_json_dto_contracts(self):
        self.assertEqual(len(self.manager.get_projects_overview().projects), 2)
        self.assertEqual(len(RuleManager("minimalist").get_projects_overview().projects), 1)
        self.assertIn("DH-project-admins", [g.name for g in self.manager.get_user_group_memberships("true", "dlinssen").groups])
        self.assertNotIn("DH-project-admins", [g.name for g in self.manager.get_user_group_memberships("true", "minimalist").groups])
        self.assertEqual(len(self.manager.get_collections("/nlmumc/projects/" + PID).collections), 2)
        self.assertIsInstance(RuleJSONManager("dlinssen").get_collections("/nlmumc/projects/" + PID), list)
        self.assertIsInstance(RuleJSONManager("dlinssen").get_collection_tree(PID + "/" + CID), list)
        self.assertTrue(self.manager.get_project_resource_availability(PID, "true", "false", "false").boolean)
        self.assertEqual(len(self.manager.get_collection_size_per_resource(PID).collection_sizes), 2)

    def test_metadata_and_discarded_writes(self):
        import jsonschema
        before = self.manager.read_instance_from_collection(PID, CID)
        jsonschema.Draft4Validator(self.manager.read_schema_from_collection(PID, CID)).validate(before)
        self.assertEqual(before, self.manager.read_instance_version_from_collection(PID, CID, "1"))
        self.assertIn("properties", self.manager.read_schema_from_collection(PID, CID))
        schema = {"overwrite": False, "schema_version": "1.0.0", "schema_file_name": "DataHub_general_schema", "title": "Changed"}
        self.assertTrue(self.manager.save_metadata_json_to_collection(PID, CID, {"changed": True}, schema).boolean)
        self.assertEqual(before, self.manager.read_instance_from_collection(PID, CID))
        self.manager.set_collection_avu(CP, "title", "Changed")
        self.assertEqual(self.manager.get_collection_attribute_value(CP, "title").value, "Example dataset")
        self.assertIn("schema", self.manager.read_metadata_from_dropzone("mock-direct", "direct"))
        self.manager.edit_drop_zone("mock-direct", PID, "Changed", "direct")
        self.assertEqual(self.manager.get_active_drop_zone("mock-direct", "true", "direct").title, "Mock direct upload")
        for typ in ("direct", "mounted"):
            self.assertEqual(self.manager.create_drop_zone({"dropzone_type": typ, "user": "dlinssen", "project": PID, "title": "New"}, str(ROOT / "fixtures/schema.json"), before, "DataHub_general_schema", "1.0.0"), "mock-" + typ)
            self.manager.ingest("dlinssen", "mock-" + typ, typ)
            self.manager.remove_dropzone("mock-" + typ, typ)
        self.manager.archive_project_collection(CP, "dlinssen")
        self.manager.unarchive_project_collection(CP, "dlinssen")

    def test_streams_and_passwords(self):
        file, info = self.manager.download_file(PID + "/" + CID + "/example.txt")
        with file:
            content = file.read()
        self.assertEqual(content, (ROOT / "fixtures/example.txt").read_bytes())
        self.assertEqual(len(content), info.size)
        with self.manager.open_data_object("/nlmumc/ingest/direct/mock-direct/new.txt", "w") as stream:
            self.assertEqual(stream.write(b"discard me"), 10)
            self.assertEqual(stream.seek(0, 2), 10)
        self.assertFalse(self.manager.does_data_object_exist("/nlmumc/ingest/direct/mock-direct/new.txt"))
        with self.assertRaises(OBJ_PATH_DOES_NOT_EXIST):
            self.manager.open_data_object(CP + "/missing.txt", "r")
        admin = RuleJSONManager(admin_mode=True)
        first = admin.generate_temporary_password("dlinssen", 10044)
        self.assertEqual(first, admin.generate_temporary_password("dlinssen", 10044))
        self.assertEqual(len(first["temporary_password"]), 32)

    def test_unknown_rules_return_native_error(self):
        with self.assertRaises(SYS_NOT_SUPPORTED):
            Rule(self.manager.session, body="unsupportedRule();").execute()


if __name__ == "__main__":
    unittest.main()
