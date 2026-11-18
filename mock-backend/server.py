"""Development iRODS TCP server backed by the immutable fixture catalog."""
import base64
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import ssl
import struct
from io import BytesIO
from pathlib import PurePosixPath
from socketserver import BaseRequestHandler, ThreadingTCPServer
from threading import Thread
from xml.etree import ElementTree as ET

from irods import MAX_PASSWORD_LENGTH, exception as ex, password_obfuscation
from irods.api_number import api_number
from irods import message as m
from werkzeug.serving import make_server

from app import DATA, MANIFEST, FixtureError, app, check_path, decode_params, file_bytes, select
from catalog import Catalog, ZONE, collection_row, result

LOGGER = logging.getLogger(__name__)
API_NAMES = {number: name for name, number in api_number.items()}
VERSION = "rods4.3.3"
RULE_CALL = re.compile(r'\b(\w+)\s*\(([^();]*)\)|\b(editIngest)\s*;')
TEMP_SALT = "mock-irods-temporary-password"
MAX_BODY = 32 * 1024 * 1024
WRITE_REQUESTS = {
    "COLL_CREATE_AN", "RM_COLL_AN", "DATA_OBJ_RENAME_AN", "DATA_OBJ_COPY_AN", "DATA_OBJ_UNLINK_AN",
}
FILE_REQUESTS = {"DATA_OBJ_OPEN_AN", "DATA_OBJ_CREATE_AN", "GET_RESOURCE_INFO_FOR_OPERATION_AN"}
DESCRIPTOR_REQUESTS = {"DATA_OBJ_READ_AN", "DATA_OBJ_WRITE_AN", "DATA_OBJ_LSEEK_AN", "DATA_OBJ_CLOSE_AN"}


def read_exact(sock, size):
    buffer = bytearray()
    while len(buffer) < size:
        chunk = sock.recv(size - len(buffer))
        if not chunk:
            raise EOFError
        buffer.extend(chunk)
    return bytes(buffer)


def read_header(sock):
    length, = struct.unpack(">I", read_exact(sock, 4))
    if not 0 < length <= 4096:
        raise ValueError("Invalid iRODS header length")
    root = ET.fromstring(read_exact(sock, length))
    values = tuple(int(root.findtext(field)) for field in ("msgLen", "errorLen", "bsLen", "intInfo"))
    if any(size < 0 for size in values[:3]) or sum(values[:3]) > MAX_BODY:
        raise ValueError("Invalid iRODS body length")
    return (root.findtext("type"), *values)


def receive(sock):
    kind, message_len, error_len, binary_len, status = read_header(sock)
    return m.iRODSMessage(
        kind, read_exact(sock, message_len) or None, read_exact(sock, error_len),
        read_exact(sock, binary_len), status,
    )


def reply(body=None, status=0, data=b"", kind="RODS_API_REPLY"):
    return m.iRODSMessage(kind, msg=body, bs=data, int_info=status)


def error_reply(error, message=None):
    code = error.code if error.code else -1
    error_text = str(error) if message is None else message
    # The PRC's XML parser expects a nonempty element.
    error_item = m.ErrorMessage(status=code, msg=error_text or type(error).__name__)
    stack = m.Error(count=1, RErrMsg_PI=[error_item])
    return m.iRODSMessage("RODS_API_REPLY", error=stack.pack(), int_info=code)


class FileHandle:
    """Read fixture bytes and track write offsets without retaining uploaded content."""

    def __init__(self, path, data, writable, created):
        self.path = path
        self.data = BytesIO(data)
        self.size = len(data)
        self.writable = writable
        self.created = created

    def seek(self, offset, whence):
        if whence == os.SEEK_END:
            return self.data.seek(self.size + offset)
        return self.data.seek(offset, whence)

    def write(self, length):
        offset = self.data.seek(length, os.SEEK_CUR)
        self.size = max(self.size, offset)


class Connection(BaseRequestHandler):
    def handle(self):
        self.sock = self.request
        self.sock.settimeout(120)
        self.challenge = None
        self.catalog = None
        self.handles = {}
        self.next_descriptor = 3
        self.pending_sizes = {}
        self.failed_authentication = False
        try:
            self.startup()
            while not self.failed_authentication:
                request = receive(self.sock)
                if request.msg_type == "RODS_DISCONNECT":
                    if isinstance(self.sock, ssl.SSLSocket):
                        self.sock.settimeout(2)
                        self.sock = self.sock.unwrap()
                    break
                if request.msg_type != "RODS_API_REQ":
                    raise ValueError(f"Unsupported iRODS message: {request.msg_type}")
                try:
                    response = self.dispatch(request)
                except FixtureError as error:
                    exception_type = {
                        "UnknowniRODSError": ex.UnknowniRODSError,
                        "DataObjectDoesNotExist": ex.OBJ_PATH_DOES_NOT_EXIST,
                        "MockBackendError": ex.SYS_NOT_SUPPORTED,
                    }.get(error.kind) or getattr(ex, error.kind, ex.SYS_INVALID_INPUT_PARAM)
                    status = exception_type() if error.status != 400 else ex.SYS_INVALID_INPUT_PARAM()
                    response = error_reply(status, error.message)
                except ex.iRODSException as error:
                    response = error_reply(error)
                except (ValueError, ET.ParseError, AttributeError, TypeError):
                    LOGGER.debug("Malformed iRODS API request %s", request.int_info, exc_info=True)
                    response = error_reply(ex.SYS_INVALID_INPUT_PARAM(), "Malformed mock iRODS request")
                self.sock.sendall(response.pack())
        except (EOFError, OSError):
            pass
        except (ValueError, ET.ParseError, AttributeError) as error:
            LOGGER.debug("Invalid request from %s: %s", self.client_address, error)
        finally:
            self.sock.close()

    def startup(self):
        packet = receive(self.sock)
        if packet.msg_type != "RODS_CONNECT":
            raise ValueError("Expected RODS_CONNECT")
        startup = ET.fromstring(packet.msg)
        self.proxy_user = startup.findtext("proxyUser")
        self.client_user = startup.findtext("clientUser")
        self.proxy_zone = startup.findtext("proxyRcatZone")
        self.client_zone = startup.findtext("clientRcatZone")
        use_tls = False
        if "request_server_negotiation" in (startup.findtext("option") or ""):
            policy = "CS_NEG_REQUIRE" if self.server.tls else "CS_NEG_REFUSE"
            negotiation = m.ClientServerNegotiation(status=1, result=policy)
            self.sock.sendall(reply(negotiation, kind="RODS_CS_NEG_T").pack())
            response = receive(self.sock).get_main_message(m.ClientServerNegotiation)
            if response.status != 1:
                raise EOFError
            use_tls = "CS_NEG_USE_SSL" in response.result
            if use_tls != bool(self.server.tls):
                raise ValueError("Negotiated transport does not match mock policy")
        version = m.VersionResponse(status=0, relVersion=VERSION, apiVersion="d",
                                    reconnPort=0, reconnAddr="", cookie=0)
        self.sock.sendall(reply(version, kind="RODS_VERSION").pack())
        if use_tls:
            self.sock = self.server.tls.wrap_socket(self.sock, server_side=True)
            # iRODS sends an SSL settings header with no body, then a shared
            # secret header followed by key bytes. The mock uses TLS itself.
            read_header(self.sock)
            kind, key_length, _, _, _ = read_header(self.sock)
            if kind != "SHARED_SECRET" or not 0 < key_length <= 64:
                raise ValueError("Invalid iRODS shared secret")
            read_exact(self.sock, key_length)

    def verify_auth(self, username, digest):
        password = self.server.password
        if self.proxy_user != "rods":
            password = self.server.user_password
        padded = struct.pack(f"{MAX_PASSWORD_LENGTH}s", password.encode().strip())
        expected = hashlib.md5(self.challenge.encode() + padded).digest().replace(b"\0", b"\1")
        if not hmac.compare_digest(digest, expected) and self.proxy_user != "rods":
            temporary = password_obfuscation.create_temp_password(TEMP_SALT, self.server.password)
            padded = struct.pack(f"{MAX_PASSWORD_LENGTH}s", temporary.encode())
            expected = hashlib.md5(self.challenge.encode() + padded).digest().replace(b"\0", b"\1")
        if username != self.proxy_user or not hmac.compare_digest(digest, expected):
            self.failed_authentication = True
            raise ex.CAT_INVALID_AUTHENTICATION("Invalid mock credentials")
        if self.proxy_zone != ZONE or self.client_zone != ZONE:
            self.failed_authentication = True
            raise ex.CAT_INVALID_CLIENT_USER("Unknown mock zone")
        self.identity = "admin" if self.client_user == "rods" else self.client_user
        if self.identity not in DATA["identities"] or (
            self.proxy_user != "rods" and (self.proxy_user != self.client_user or self.identity == "admin")
        ):
            self.failed_authentication = True
            raise ex.CAT_INVALID_CLIENT_USER("Unknown or unauthorized mock user")
        self.catalog = Catalog(self.identity)

    def authenticate(self, name, request):
        if name == "AUTH_REQUEST_AN":
            self.challenge = secrets.token_hex(32)
            return reply(m.AuthChallenge(challenge=self.challenge.encode()))
        if name == "AUTH_RESPONSE_AN" and self.challenge:
            response = request.get_main_message(m.AuthResponse)
            self.verify_auth(response.username, response.response)
            self.challenge = None
            return reply()
        if name == "AUTHENTICATION_APN":
            payload = request.get_json_encoded_struct()
            operation = payload.get("next_operation")
            if payload.get("scheme") == "native" and operation == "auth_agent_auth_request":
                self.challenge = secrets.token_hex(32)
                return reply(m.JSON_Message({
                    "scheme": "native", "user_name": self.proxy_user, "zone_name": self.proxy_zone,
                    "request_result": self.challenge,
                }, (4, 3, 3)))
            if payload.get("scheme") == "native" and operation == "auth_agent_auth_response" and self.challenge:
                self.verify_auth(payload.get("user_name"), base64.b64decode(payload["digest"], validate=True))
                self.challenge = None
                return reply(m.JSON_Message({"next_operation": "authentication_flow_complete"}, (4, 3, 3)))
        self.failed_authentication = True
        raise ex.CAT_INVALID_AUTHENTICATION("The mock supports native password authentication")

    def dispatch(self, request):
        name = API_NAMES.get(request.int_info)
        if self.catalog is None:
            return self.authenticate(name, request)
        if name == "EXEC_MY_RULE_AN":
            return self.execute_rule(ET.fromstring(request.msg))
        if name == "GEN_QUERY_AN":
            return reply(self.catalog.query(request.get_main_message(m.GenQueryRequest)))
        if name == "SPECIFIC_QUERY_AN":
            return self.specific_query(request.get_main_message(m.SpecificQueryRequest))
        if name in ("GET_MISC_SVR_INFO_AN", "END_TRANSACTION_AN"):
            return reply()
        if name == "GET_TEMP_PASSWORD_FOR_OTHER_AN":
            target = request.get_main_message(m.GetTempPasswordForOtherRequest).targetUser
            if self.identity != "admin":
                raise ex.CAT_NO_ACCESS_PERMISSION()
            if target not in DATA["users"]:
                raise ex.CAT_SQL_ERR()
            return reply(m.GetTempPasswordForOtherOut(stringToHashWith=TEMP_SALT))
        if name == "GET_TEMP_PASSWORD_AN":
            return reply(m.GetTempPasswordOut(stringToHashWith=TEMP_SALT))
        if name in WRITE_REQUESTS:
            return self.write_request(name, request)
        if name in FILE_REQUESTS:
            return self.open_file(name, request.get_main_message(m.FileOpenRequest))
        if name in DESCRIPTOR_REQUESTS:
            return self.file_operation(name, request)
        raise ex.SYS_NOT_SUPPORTED(f"Mock iRODS API not implemented: {name or request.int_info}")

    def execute_rule(self, request):
        params = {
            node.findtext("label"): node.findtext("STR_PI/myStr", default="")
            for node in request.findall("MsParamArray_PI/MsParam_PI")
        }
        rule = request.findtext("myRule", default="")
        matched = [(name or custom, args) for name, args, custom in RULE_CALL.findall(rule)
                   if (name or custom) in MANIFEST["rules"]]
        if len(matched) != 1:
            raise ex.SYS_NOT_SUPPORTED("Expected one named fixture rule")
        name, arguments = matched[0]
        # Wrapper callers normally send numbered parameters. Also support a
        # named iRODS parameter used by standalone python-irodsclient scripts.
        for index, argument in enumerate(arguments.split(","), start=2):
            argument = argument.strip()
            if argument in params:
                params.setdefault(f"*arg{index}", params[argument])
            elif not argument.startswith("*") and argument:
                params.setdefault(f"*arg{index}", argument)
        output = json.dumps(select(name, decode_params(params), self.identity)).encode() + b"\n\0"
        param = m.MsParam(label="ruleExecOut", type="ExecCmdOut_PI", inOutStruct=m.ExecCmdOut_PI(
            stdoutBuf=m.BinBytesBuf(buflen=len(output), buf=output),
            stderrBuf=m.BinBytesBuf(buflen=1, buf=b"\0"), status=0,
        ))
        return reply(m.MsParamArray(paramLen=1, oprType=0, MsParam_PI=[param]))

    def specific_query(self, query):
        if query.sql not in ("delete_password", "count_password", "get_create_ts_password"):
            raise ex.SYS_NOT_SUPPORTED(f"Unsupported specific query: {query.sql}")
        if str(query.arg1) not in {str(row["id"]) for row in DATA["users"].values()}:
            raise ex.CAT_NO_ROWS_FOUND()
        if query.sql == "delete_password":
            if self.identity != "admin":
                raise ex.CAT_NO_ACCESS_PERMISSION()
            raise ex.CAT_NO_ROWS_FOUND()
        value = 1 if query.sql == "count_password" else 1893456000
        return reply(result([0], [{0: value}]))

    def write_request(self, name, request):
        if name in ("COLL_CREATE_AN", "RM_COLL_AN"):
            path = check_path(request.get_main_message(m.CollectionRequest).collName, self.identity)
            if name == "COLL_CREATE_AN" and path not in self.catalog.collections:
                self.catalog.pending_collection = collection_row(path, self.client_user)
        elif name in ("DATA_OBJ_RENAME_AN", "DATA_OBJ_COPY_AN"):
            source_request, target_request = ET.fromstring(request.msg).findall("DataObjInp_PI")
            source = check_path(source_request.findtext("objPath"), self.identity)
            target = check_path(target_request.findtext("objPath"), self.identity)
            if source_request.findtext("oprType") != "12":
                size = self.pending_sizes.pop(source, self.catalog.files.get(source, {}).get(407, 0))
                self.catalog.acknowledge_file(target, DATA["files"].get(source, {}), size)
        else:
            path = check_path(request.get_main_message(m.FileOpenRequest).objPath, self.identity)
            self.pending_sizes.pop(path, None)
        return reply()

    def open_file(self, name, request):
        path = check_path(request.objPath, self.identity)
        if name == "GET_RESOURCE_INFO_FOR_OPERATION_AN":
            resource = DATA["files"].get(path, {}).get("resource_name", "passRescUM01")
            return reply(m.STR_PI(myStr=json.dumps({"host": "", "resource_hierarchy": resource})))
        created = name == "DATA_OBJ_CREATE_AN"
        writable = created or bool(request.openFlags & os.O_ACCMODE)
        truncate = bool(request.openFlags & os.O_TRUNC)
        content = b"" if writable and (truncate or path not in self.catalog.files) else file_bytes(path)
        descriptor = self.next_descriptor
        self.next_descriptor += 1
        handle = FileHandle(path, content, writable, created)
        if writable and not truncate:
            handle.size = max(handle.size, self.pending_sizes.get(path, 0))
        self.handles[descriptor] = handle
        return reply(status=descriptor)

    def file_operation(self, name, request):
        operation = request.get_main_message(m.OpenedDataObjRequest)
        handle = self.handles.get(operation.l1descInx)
        if handle is None:
            raise ex.SYS_FILE_DESC_OUT_OF_RANGE()
        if name == "DATA_OBJ_READ_AN":
            data = handle.data.read(max(0, operation.len))
            return reply(status=len(data), data=data)
        if name == "DATA_OBJ_WRITE_AN":
            if not handle.writable:
                raise ex.CAT_NO_ACCESS_PERMISSION()
            length = len(request.bs)
            handle.write(length)
            return reply(status=length)
        if name == "DATA_OBJ_LSEEK_AN":
            return reply(m.FileSeekResponse(offset=handle.seek(operation.offset, operation.whence)))
        self.handles.pop(operation.l1descInx)
        if handle.created:
            # The SDK checks the new object after create. For an empty direct
            # upload, MDR then checks it again to compose the upload receipt.
            reads = 2 if handle.path.startswith(f"/{ZONE}/ingest/direct/") else 1
            self.catalog.acknowledge_file(handle.path, {}, handle.size, reads)
        if handle.writable and handle.path.endswith(".part"):
            self.pending_sizes[handle.path] = handle.size
        return reply()


class Server(ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, address, *, tls=None, password, user_password):
        self.tls = tls
        self.password = password
        self.user_password = user_password
        super().__init__(address, Connection)


def main():
    logging.basicConfig(level=logging.INFO)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(os.environ["MOCK_SERVER_CERT"], os.environ["MOCK_SERVER_KEY"])
    server = Server(("0.0.0.0", 1247), tls=tls,
                    password=os.environ["MOCK_IRODS_PASSWORD"],
                    user_password=os.environ.get("MOCK_IRODS_USER_PASSWORD", "foobar"))
    http = make_server("0.0.0.0", 5000, app, threaded=True)
    Thread(target=http.serve_forever, daemon=True).start()
    LOGGER.info("Mock listening for iRODS on port 1247")
    with server:
        server.serve_forever()


if __name__ == "__main__":
    main()
