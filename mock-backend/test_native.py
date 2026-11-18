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
