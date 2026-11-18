"""MDR integration checks against the dedicated mock DB, never a live catalog."""
import os
import sys
sys.path.insert(0, os.getcwd())
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "core.settings")
import django
django.setup()

import unittest
from unittest.mock import patch
from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client
from django.test.utils import setup_test_environment
from app.auth_backends import create_mdr_user
from app.models import CustomUser
from irodsrulewrapper.rule import RuleManager

setup_test_environment()


@unittest.skipUnless(os.environ.get("IRODS_HOST") == "mock-backend" and settings.POSTGRES_HOST == "mock-mdr-db", "Requires dedicated mock stack")
class MDRTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.users = {}
        for name, uid in (("dlinssen", 10044), ("minimalist", 10074)):
            user = CustomUser.objects.filter(username=name).first() or create_mdr_user(name, uid)
            cls.users[name] = user

    def setUp(self):
        self.client = Client()
        self.login(self.users["dlinssen"])

    def login(self, user):
        # Client.force_login constructs a bare HttpRequest without request.user.
        # The real login signal and its local help endpoint are covered in Chromium.
        with patch("app.views.home.set_help_center_uuid"):
            self.client.force_login(user)

    def test_pages_for_both_users(self):
        paths = ["/", "/projects/P000000001", "/projects/P000000001/C000000001/",
                 "/projects/P000000001/C000000001/edit",
                 "/hdl/P000000001/C000000001/", "/hdl/P000000001/C000000001.1/",
                 "/processes/index", "/dropzone/upload/mock-direct", "/dropzone/edit/direct/mock-direct",
                 "/dropzone/edit/mounted/mock-mounted", "/search", "/credentials", "/co/", "/requestproject"]
        for name in ("dlinssen", "minimalist"):
            self.login(self.users[name])
            for path in paths:
                with self.subTest(user=name, path=path):
                    response = self.client.get(path)
                    self.assertEqual(response.status_code, 200)
        self.assertTrue(self.users["dlinssen"].is_admin)
        self.assertFalse(self.users["minimalist"].is_admin)
        self.assertEqual(self.client.get("/createproject").status_code, 302)
        self.login(self.users["dlinssen"])
        self.assertEqual(self.client.get("/createproject").status_code, 200)
        self.assertEqual(self.client.get("/projects/changepermissions/P000000001").status_code, 200)
        self.assertEqual(self.client.get("/projects/financial").status_code, 200)
        response = self.client.post("/projects/P000000001/C000000001/change_schema", {
            "selected_schema": "DataHub_extended_schema", "changeSchema": "true",
        })
        self.assertEqual(response.status_code, 200)


    def test_development_service_endpoints(self):
        self.assertEqual(self.client.get("/djangocedar/bioportal", {"q": "dataset"}).status_code, 200)
        self.assertEqual(self.client.post("/ajax/set_help_center_uuid/").status_code, 200)

    def test_download_and_discarded_upload(self):
        response = self.client.get("/download", {"path": "P000000001/C000000001/example.txt"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"Static MDR mock dataset.\n")
        response = self.client.post("/dropzone_upload/upload?id=%2F", {"upload": SimpleUploadedFile("new.txt", b"new content")}, HTTP_REFERER="http://testserver/dropzone/upload/mock-direct")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertFalse(RuleManager("dlinssen").does_data_object_exist("/nlmumc/ingest/direct/mock-direct/new.txt"))
        for filename, contents in (("empty.txt", b""), ("nested.txt", b"example")):
            with self.subTest(filename=filename):
                response = self.client.post(
                    f"/dropzone_upload/upload?id=%2F&upload_fullpath=folder%2F{filename}",
                    {"upload": SimpleUploadedFile(filename, contents)},
                    HTTP_REFERER="http://testserver/dropzone/upload/mock-direct",
                )
                self.assertEqual(response.status_code, 200, response.content)
                self.assertEqual(response.json()["size"], len(contents))
        response = self.client.get("/dropzone_upload/files", {"id": "/"}, HTTP_REFERER="http://testserver/dropzone/upload/mock-direct")
        self.assertEqual(response.status_code, 200)

    def assertContainsMessage(self, response, text):
        self.assertIn(text, [str(message) for message in response.context["messages"]])

    def test_create_project_returns_existing_fixture_without_modifying_reads(self):
        data = {"requester": "Dean", "ticket": "MOCK-1", "email": "dean@example.org",
                "project_title": "New mock project", "project_gb": 10, "project_budget_number": "XXXXXXXXX",
                "archive_tape_storage_surf": False, "unarchive_tape_storage_surf": False,
                "shared_dropzones": True, "metadata_schemas": ["DataHub_general_schema"],
                "ingest_resource": "ires-hnas-umResource", "resource": "passRescUM01",
                "principal_investigator": "dlinssen", "data_steward": "opalmen",
                "managers": ["dlinssen", "opalmen"], "contributors": ["minimalist"], "viewers": ["auser"], "comment": "Mock"}
        response = self.client.post("/createproject", data)
        self.assertEqual(response.status_code, 200)
        self.assertContainsMessage(response, "New project created: P000000001")
        self.assertEqual(len(RuleManager("dlinssen").get_projects_overview().projects), 2)


if __name__ == "__main__":
    unittest.main()
