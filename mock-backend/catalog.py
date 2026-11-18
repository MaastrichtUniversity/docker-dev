"""Small read-only catalog for the GenQuery operations exercised by the mock."""
import re
from pathlib import PurePosixPath
from zlib import crc32

from irods import exception as ex
from irods.message import GenQueryResponse, GenQueryResponseColumn

from app import DATA, FIXTURES

ZONE = "nlmumc"
TIME = "01767268800"


def fixture_id(path):
    return 20000 + crc32(path.encode())


def file_row(path, entry, size=0):
    resource = entry.get("resource_name", "passRescUM01")
    return {
        401: fixture_id(path), 402: fixture_id(str(PurePosixPath(path).parent)),
        403: PurePosixPath(path).name, 404: 0, 405: "", 406: "generic",
        407: size, 409: resource, 410: path, 411: "rods", 412: ZONE,
        413: 1, 414: "", 415: "", 416: "", 417: 0, 418: "", 419: TIME,
        420: TIME, 422: resource, 423: fixture_id(resource),
    }


def collection_row(path, owner="rods"):
    return {
        500: fixture_id(path), 501: path, 502: str(PurePosixPath(path).parent),
        503: owner, 504: ZONE, 505: "0", 506: "0", 507: "", 508: TIME, 509: TIME,
    }


def result(columns, rows, continuation=0):
    result_columns = []
    for key in columns:
        values = [str(row[key]) for row in rows]
        result_columns.append(GenQueryResponseColumn(
            attriInx=key, reslen=max(map(len, values), default=0) + 1, value=values,
        ))
    return GenQueryResponse(
        rowCnt=len(rows), attriCnt=len(columns), continueInx=continuation,
        totalRowCount=len(rows), SqlResult_PI=result_columns,
    )


class Catalog:
    def __init__(self, user):
        projects = DATA["identities"][user]["projects"]

        def visible(path):
            return all(project in projects for project in re.findall(r"P\d{9}", path))

        users = {
            **DATA["users"],
            "rods": {"id": 10, "name": "rods", "type": "rodsadmin"},
            "service-disqover": {"id": 10096, "name": "service-disqover", "type": "rodsuser"},
        }
        self.users = [
            {201: row["id"], 202: name, 203: row["type"], 204: ZONE,
             206: "", 207: "", 208: TIME, 209: TIME}
            for name, row in users.items()
        ]
        groups = next(row["result"] for row in DATA["rules"]["get_groups"])
        self.groups = [{900: group["groupId"], 901: group["name"]} for group in groups]
        resource_names = {entry.get("resource_name", "passRescUM01") for entry in DATA["files"].values()}
        self.resources = [
            {301: fixture_id(name), 302: name, 303: ZONE, 304: "unixfilesystem",
             305: "cache", 306: "mock-backend", 307: "/mock", 308: "", 310: "",
             311: TIME, 312: TIME, 313: "up", 314: TIME, 315: "", 316: "", 317: "", 318: ""}
            for name in sorted(resource_names)
        ]
        self.files = {
            path: file_row(path, entry, (FIXTURES / entry["fixture"]).stat().st_size)
            for path, entry in DATA["files"].items() if visible(path)
        }
        directory_paths = {path for path in DATA["directories"] if visible(path)}
        directory_paths.update(f"/{ZONE}/home/{name}" for name in users)
        directory_paths.update(
            str(parent) for path in (*directory_paths, *self.files)
            for parent in PurePosixPath(path).parents
        )
        self.collections = {path: collection_row(path) for path in sorted(directory_paths)}
        self.pending_collection = None
        self.pending_file = None
        self.pending_file_reads = 0
        self._page = None

    def acknowledge_file(self, path, entry, size, reads=1):
        self.pending_file = file_row(path, entry, size)
        self.pending_file_reads = reads

    def query(self, query):
        columns = query.InxIvalPair_PI.inx or []
        modifiers = query.InxIvalPair_PI.ivalue or []
        if query.continueInx:
            if query.continueInx != 1 or self._page is None:
                raise ex.CAT_NO_ROWS_FOUND()
            remaining = self._page
        else:
            filters = list(zip(query.InxValPair_PI.inx or [], query.InxValPair_PI.svalue or []))
            remaining = self._rows(columns, modifiers, filters, ignore_case=bool(query.options & 0x200))
            remaining = remaining[query.partialStartIndex:]
        if not remaining or query.maxRows == 0:
            self._page = None
            raise ex.CAT_NO_ROWS_FOUND()
        self._page = remaining[query.maxRows:] or None
        return result(columns, remaining[:query.maxRows], continuation=int(self._page is not None))

    def _rows(self, columns, modifiers, filters, ignore_case):
        keys = set(columns) | {key for key, _ in filters}
        families = [
            ({101, 102, 103}, [{101: 1, 102: ZONE, 103: "local"}]),
            (set(self.users[0]), self.users),
            ({900, 901}, self.groups),
            (set(self.resources[0]), self.resources),
        ]
        if keys <= set(collection_row("/")):
            rows = list(self.collections.values())
            pending = self.pending_collection
            if pending and (501, f"= '{pending[501]}'") in filters:
                rows.append(pending)
                self.pending_collection = None
            elif self.pending_file:
                # A directory created during a fixture upload is available to
                # the SDK for the immediate stat of the discarded upload.
                parent = str(PurePosixPath(self.pending_file[410]).parent)
                if parent not in self.collections and (501, f"= '{parent}'") in filters:
                    rows.append(collection_row(parent))
        elif keys <= set(file_row("/", {})) | set(collection_row("/")):
            pending = self.pending_file
            exact = pending and all(
                pair in filters for pair in ((402, f"= '{pending[402]}'"), (403, f"= '{pending[403]}'"))
            )
            files = dict(self.files)
            if exact:
                files[pending[410]] = pending
                self.pending_file_reads -= 1
                if not self.pending_file_reads:
                    self.pending_file = None
            rows = [
                {**self.collections.get(str(PurePosixPath(path).parent),
                                        collection_row(str(PurePosixPath(path).parent))), **row}
                for path, row in files.items()
            ]
        else:
            rows = next((rows for family, rows in families if keys <= family), None)
            if rows is None:
                raise ex.SYS_NOT_SUPPORTED(f"Unsupported fixture query columns: {sorted(keys)}")
        rows = [row for row in rows if all(matches(row[key], clause, ignore_case) for key, clause in filters)]
        for key, modifier in reversed(list(zip(columns, modifiers))):
            if modifier & 0xC00:
                rows.sort(key=lambda row: row[key], reverse=bool(modifier & 0x800))
            elif modifier != 1:
                raise ex.SYS_NOT_SUPPORTED("Aggregate GenQuery is outside the fixture catalog")
        return rows


def matches(value, clause, ignore_case):
    predicate = re.fullmatch(r"(=|!=|<>|like|not like) '(.*)'", clause, re.IGNORECASE)
    if not predicate:
        raise ex.SYS_NOT_SUPPORTED(f"Unsupported fixture query predicate: {clause}")
    operator, term = predicate.groups()
    value = str(value)
    if ignore_case:
        term, value = term.upper(), value.upper()
    if operator.lower() in ("like", "not like"):
        wildcard = "".join(".*" if c == "%" else "." if c == "_" else re.escape(c) for c in term)
        return bool(re.fullmatch(wildcard, value)) == (operator.lower() == "like")
    return (value == term) == (operator == "=")
