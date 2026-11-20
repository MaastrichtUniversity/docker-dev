"""Run inside the Flask image: python -m unittest test_backend."""
import ast
import copy
import json
import os
import re
import unittest
from pathlib import Path

from app import app, DATA, MANIFEST, FIXTURES

RULESET = Path(os.environ.get("RULESET_ROOT", FIXTURES.parent.parent / "externals/irods-ruleset"))


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def post(self, path, arguments=None, user="dlinssen"):
        return self.client.post(path, json={"client_user": user, "admin_mode": user == "admin",
                                           "arguments": arguments or {}})

    def test_all_rule_contracts_have_deterministic_fixtures(self):
        self.assertEqual(set(MANIFEST["rules"]), set(DATA["rules"]))
        for name, rows in DATA["rules"].items():
            for row in rows:
                arguments = {key: json.dumps(value) for key, value in row["match"].items()}
                for user in row["users"]:
                    with self.subTest(rule=name, user=user, arguments=arguments):
                        first = self.post("/rules/" + name, arguments, user)
                        self.assertEqual(first.status_code, 403 if "error" in row else 200, first.data)
                        self.assertEqual(first.data, self.post("/rules/" + name, arguments, user).data)

    def test_manifest_covers_ruleset_exports(self):
        if not RULESET.is_dir():
            self.skipTest("Set RULESET_ROOT to the irods-ruleset checkout")
        public = set()
        for source in (RULESET / "datahubirodsruleset").glob("*/__init__.py"):
            text = source.read_text()
            lines = text.splitlines()
            for node in ast.parse(text).body:
                if isinstance(node, ast.ImportFrom):
                    sections = [line for line in lines[:node.lineno]
                                if line in ("# Public rules", "# Private rules")]
                    if sections and sections[-1] == "# Public rules":
                        public.update(alias.asname or alias.name for alias in node.names)
        native = set()
        for source in (RULESET / "native_irods_ruleset").rglob("*.r"):
            dummy = re.search(r"^irule_dummy\(\)\s*\{(.*?)^\}", source.read_text(), re.M | re.S)
            if dummy:
                native.update(re.findall(r"\bIRULE_(\w+)\s*\(", dummy[1]))
        self.assertTrue(public and native)
        contracts = MANIFEST["rules"]
        self.assertEqual(native, {name for name, contract in contracts.items() if contract.get("native")})
        self.assertEqual(contracts.keys(), public | native | {
            name for name, contract in contracts.items() if "file" in contract
        })

    def test_writes_do_not_change_reads_or_fixture_data(self):
        before = copy.deepcopy(DATA)
        projects = self.post("/rules/optimized_list_projects").data
        self.post("/rules/setCollectionAVU", {"*arg2": '"/nlmumc/projects/P000000001"', "*arg3": '"title"', "*arg4": '"changed"'})
        self.post("/api/data_objects.create", {"path": "/nlmumc/ingest/direct/mock-direct/new.txt"})
        self.post("/api/collections.remove", {"path": "/nlmumc/projects/P000000001", "force": True})
        self.assertEqual(projects, self.post("/rules/optimized_list_projects").data)
        self.assertEqual(before, DATA)
        self.assertFalse(self.post("/api/data_objects.exists", {"path": "/nlmumc/ingest/direct/mock-direct/new.txt"}).json)

    def test_every_write_accepts_missing_and_invalid_arguments(self):
        before = copy.deepcopy(DATA)
        for name, contract in MANIFEST["rules"].items():
            if contract.get("write"):
                with self.subTest(rule=name):
                    fixture, = [row for row in DATA["rules"][name] if not row["match"]]
                    for arguments in ({}, {"*arg2": "missing,{invalid};(value)", "*arg3": "/missing"}):
                        response = self.post("/rules/" + name, arguments, "minimalist")
                        self.assertEqual(response.status_code, 200, response.data)
                        self.assertEqual(response.json, fixture["result"])
        self.assertEqual(before, DATA)

    def test_users_have_different_project_visibility(self):
        self.assertEqual(len(self.post("/rules/optimized_list_projects").json), 2)
        self.assertEqual(len(self.post("/rules/optimized_list_projects", user="minimalist").json), 1)
        self.assertEqual(self.post("/api/data_objects.open", {"path": "/nlmumc/projects/P000000002/C000000001/example.txt", "mode": "r"}, "minimalist").status_code, 403)

    def test_missing_operations_and_files_are_explicit_errors(self):
        for path, args in [("/rules/not_a_rule", {}), ("/api/not_an_operation", {}),
                           ("/api/data_objects.open", {"path": "/nlmumc/projects/P000000001/missing.txt", "mode": "r"})]:
            response = self.post(path, args)
            self.assertEqual(response.status_code, 404)
            self.assertIn("error", response.json)
        self.assertEqual(self.post("/rules/get_users", user="unknown").status_code, 403)
        self.assertEqual(self.post("/api/data_objects.open", {"path": "/nlmumc/../secret", "mode": "r"}).status_code, 400)

    def test_search_filters_are_repeatable_and_do_not_need_elasticsearch(self):
        request = {"client_user": "minimalist", "search": "", "access_filter": True}
        self.assertEqual(len(self.client.post("/integrations/search", json=request).json), 2)
        request["access_filter"] = False
        self.assertEqual(len(self.client.post("/integrations/search", json=request).json), 4)
        request["search"] = "does-not-exist"
        self.assertEqual(self.client.post("/integrations/search", json=request).json, [])

    def test_fixture_files_exist(self):
        for entry in DATA["files"].values():
            self.assertTrue((FIXTURES / entry["fixture"]).is_file())
        for rule_rows in DATA["rules"].values():
            for row in rule_rows:
                for filename in row.get("result_files", {}).values():
                    json.loads((FIXTURES / filename).read_text())


if __name__ == "__main__":
    unittest.main()
