"""TCP interoperability checks using just python-irodsclient."""
import io
import json
import os
import ssl
import unittest

from irods.exception import CAT_INVALID_AUTHENTICATION, OBJ_PATH_DOES_NOT_EXIST, SYS_NOT_SUPPORTED
from irods.models import Collection, DataObject
from irods.rule import Rule
from irods.session import iRODSSession

from app import DATA, MANIFEST
from test_backend import RULESET

PROJECT = "/nlmumc/projects/P000000001"
EXAMPLE = PROJECT + "/C000000001/example.txt"


class NativeClientTests(unittest.TestCase):
    def connect(self, user="minimalist", password="foobar", tls=False, **options):
        if tls:
            options.update(
                irods_client_server_negotiation="request_server_negotiation",
                irods_client_server_policy="CS_NEG_REQUIRE",
                irods_encryption_algorithm="AES-256-CBC", irods_encryption_key_size=32,
                irods_encryption_num_hash_rounds=16, irods_encryption_salt_size=8,
                ssl_context=ssl.create_default_context(cafile=os.environ.get("MOCK_CA", "/mock-ca/ca.pem")),
            )
        session = iRODSSession(
            host=os.environ.get("MOCK_HOST", "localhost"),
            port=int(os.environ.get("MOCK_PORT", "1247")),
            zone="nlmumc", user=user, password=password, **options,
        )
        self.addCleanup(session.cleanup)
        return session

    def test_catalog_files_and_queries(self):
        client = self.connect()
        self.assertEqual(client.users.get("minimalist").name, "minimalist")
        self.assertEqual(client.collections.get(PROJECT).path, PROJECT)
        self.assertFalse(client.collections.exists("/nlmumc/projects/P000000002"))
        subcollections = list(client.query(Collection.name).filter(Collection.parent_name == PROJECT))
        self.assertTrue(any(row[Collection.name] == PROJECT + "/C000000001" for row in subcollections))
        with client.data_objects.open(EXAMPLE, "r") as file:
            self.assertEqual(file.read(6), b"Static")
            file.seek(0)
            self.assertEqual(file.read(), b"Static MDR mock dataset.\n")
        self.assertEqual(client.data_objects.get(EXAMPLE).size, len(b"Static MDR mock dataset.\n"))
        self.assertTrue(list(client.query(DataObject.name).filter(DataObject.name == "example.txt")))

    def test_tls_proxy_and_named_rule(self):
        client = self.connect("rods", os.environ.get("MOCK_IRODS_PASSWORD", "mock"),
                              tls=True, client_user="minimalist")
        script = io.BytesIO(b'main { list_projects_minimal(*result); writeLine("stdout", *result); }\nOUTPUT ruleExecOut\n')
        answer = Rule(client, rule_file=script).execute()
        projects = json.loads(answer.MsParam_PI[0].inOutStruct.stdoutBuf.buf.rstrip(b"\0"))
        self.assertEqual([project["id"] for project in projects], ["P000000001"])

    def test_added_rules_for_both_fixture_users(self):
        for user in ("dlinssen", "minimalist"):
            client = self.connect(user)
            for name, contract in MANIFEST["rules"].items():
                if "file" in contract:
                    continue
                with self.subTest(user=user, rule=name):
                    fixture = max((row for row in DATA["rules"][name] if user in row["users"]),
                                  key=lambda row: len(row["match"]))
                    positions = contract.get("outputs", [])
                    inputs = {int(key[4:]) - 2: value for key, value in fixture["match"].items()}
                    arguments = [
                        f"*p{i}" for i in range(max([*positions, *inputs], default=-1) + 1)
                    ]
                    params = {arguments[i]: json.dumps(value) for i, value in inputs.items()}
                    labels = [arguments[i] for i in positions]
                    body = f"{name}({', '.join(arguments)});"
                    body += "".join(f' writeLine("stdout", {label});' for label in labels)
                    output = "%".join(["ruleExecOut", *labels])
                    answer = Rule(client, body=body, params=params, output=output).execute(session_cleanup=False)
                    values = fixture["result"] if len(positions) > 1 else [fixture["result"]]
                    expected = [value if isinstance(value, str) else json.dumps(value)
                                for value in values] if positions else []
                    self.assertEqual([p.label for p in answer.MsParam_PI], ["ruleExecOut", *labels])
                    self.assertEqual([p.inOutStruct.myStr or "" for p in answer.MsParam_PI[1:]], expected)
                    self.assertEqual(answer.MsParam_PI[0].inOutStruct.stdoutBuf.buf.rstrip(b"\0").decode(),
                                     "".join(value + "\n" for value in expected))

    def test_report_visibility_and_shared_zone_settings(self):
        for user, projects in (
            ("dlinssen", ["P000000001", "P000000002"]),
            ("minimalist", ["P000000001"]),
        ):
            with self.subTest(user=user):
                client = self.connect(user)
                answer = Rule(client, body="reportProjects(*report);", output="*report").execute()
                self.assertEqual([row["project"] for row in json.loads(answer.MsParam_PI[0].inOutStruct.myStr)],
                                 projects)
                answer = Rule(client, body="get_ingest_maintenance_window(*window);", output="*window").execute()
                self.assertEqual(json.loads(answer.MsParam_PI[0].inOutStruct.myStr),
                                 {"maintenanceStart": None, "maintenanceEnd": None})

    def test_legacy_rule_file_and_raw_stdout(self):
        client = self.connect()
        script = io.BytesIO(b'''
# IRULE_calcCollectionFiles(*mock, *ignored) is only a comment.
irule_dummy() {
    IRULE_getCollectionAVU(*path, "title", *value, "", 'false');
    writeLine("stdout", *value);
}
IRULE_getCollectionAVU(*path, *attribute, *value, *default, *fatal) {
    fake_unsupported_call(*value);
}
INPUT *path=""
OUTPUT ruleExecOut
''')
        answer = Rule(client, rule_file=script, params={"*path": f"'{PROJECT}'"}).execute()
        self.assertEqual(answer.MsParam_PI[0].inOutStruct.stdoutBuf.buf.rstrip(b"\0"),
                         b"Shared microscopy study\n")

    def test_native_rule_files_keep_entry_point_output(self):
        if not RULESET.is_dir():
            self.skipTest("Set RULESET_ROOT to the irods-ruleset checkout")
        client = self.connect()
        for filename, args, stdout in (
            ("tapeArchive/estimateProjectCollection.r", {"*project": "P000000001", "*collection": "C000000001"},
             b"0\n0\n"),
            ("misc/getResourceAVU.r", {"*resourceName": "passRescUM01", "*attribute": "NCIT:C88193"},
             b"0.130\n"),
            ("projects/changeProjectPermissions.r", {"*project": "/missing", "*users": '(bad,"value");'},
             b""),
        ):
            with self.subTest(rule_file=filename):
                path = RULESET / "native_irods_ruleset" / filename
                answer = Rule(client, rule_file=str(path), params=args).execute(session_cleanup=False)
                self.assertEqual(answer.MsParam_PI[0].inOutStruct.stdoutBuf.buf.rstrip(b"\0"), stdout)

    def test_named_writes_ignore_invalid_arguments_and_leave_reads_unchanged(self):
        client = self.connect()
        read = 'get_ingest_maintenance_window(*window);'
        before = Rule(client, body=read, output="*window").execute().MsParam_PI[0].inOutStruct.myStr
        write = 'set_ingest_maintenance_window("(invalid),value;", "wrong");'
        self.assertFalse(Rule(client, body=write).execute().MsParam_PI)
        answer = Rule(client, body='delete_user("/missing", *result);', output="*result").execute()
        self.assertIs(json.loads(answer.MsParam_PI[0].inOutStruct.myStr)["success"], True)
        after = Rule(client, body=read, output="*window").execute().MsParam_PI[0].inOutStruct.myStr
        self.assertEqual(before, after)

    def test_writes_preserve_fixed_directory_and_files(self):
        client = self.connect()
        new_directory = PROJECT + "/C000000001/created"
        self.assertEqual(client.collections.create(new_directory).path, new_directory)
        self.assertFalse(client.collections.exists(new_directory))
        new_file = PROJECT + "/C000000001/created.txt"
        with client.data_objects.open(new_file, "w") as file:
            self.assertEqual(file.write(b"discard"), 7)
        with self.assertRaises(OBJ_PATH_DOES_NOT_EXIST):
            client.data_objects.open(new_file, "r")
        self.assertTrue(client.data_objects.exists(EXAMPLE))

    def test_bad_password_and_unknown_rule(self):
        with self.assertRaises(CAT_INVALID_AUTHENTICATION):
            self.connect(password="wrong").collections.get(PROJECT)
        with self.assertRaises(SYS_NOT_SUPPORTED):
            Rule(self.connect(), body="unknown_rule();").execute()


if __name__ == "__main__":
    unittest.main()
