# Native iRODS fixture server

From docker-dev, start only the Python server:

```sh
./rit.sh mock backend
```

A client in the `dh_default` Docker network can use `mock-backend:1247`.
A client on the Docker host can use `localhost:1247`. If that host port is
occupied, start with `MOCK_IRODS_PORT=1249 ./rit.sh mock backend` and use
port 1249 from the host. The port inside Docker is always 1247.

Use zone `nlmumc` and either fixture user `dlinssen` or `minimalist` with
password `foobar`. The proxy administrator is `rods` with password `mock`.
Set `MOCK_IRODS_PASSWORD` before startup to choose a different development
proxy password.

```python
from irods.session import iRODSSession

with iRODSSession(
    host="localhost", port=1247, zone="nlmumc",
    user="minimalist", password="foobar",
) as session:
    print(session.collections.get("/nlmumc/projects/P000000001").path)
```

MDR configures its Python client to require TLS and verify the server. The
mock generates a development certificate on first startup, and Compose
provides the public certificate to MDR through a read-only mount. For a
separately configured client using verified TLS, copy the public certificate
with `docker cp dev-mock-backend-1:/mock-ca/ca.pem ./mock-irods-ca.pem`
and configure your existing client's trust settings. Use a hostname on the
certificate (`mock-backend`, `localhost` or `127.0.0.1`).

## Start with MDR

```sh
./rit.sh mock
```

The mock Compose override sets `IRODS_HOST=mock-backend` and supplies the
fixture proxy password and TLS trust. It starts MDR with its standard
settings and normal `python-irodsclient`. There is no application shim.
It also starts a separate MDR PostgreSQL database, Keycloak and LDAP. The
common reverse proxy is reused or started if absent. Open the MDR URL
printed by the command. On a local Docker host, add the MDR and Keycloak
virtual hostnames to your hosts file if they do not already resolve there.

| Keycloak account | Fixture access |
| --- | --- |
| `dlinssen` | Administrator and manager of two projects |
| `minimalist` | Contributor to the shared microscopy project |

The Keycloak fixture password is `foobar` for web login. The native iRODS
fixture accounts use the passwords described above.

Docker Compose 2.24.4 or newer is required for the override. The standalone
mock uses a Python image and installs no iRODS server packages. The existing
MDR Dockerfile installs an amd64 Filebeat package. If a full mock stack needs
to run on ARM, the existing MDR and other development images may require
Docker amd64 emulation.

`./rit.sh mock off` restores MDR's native backend and original database.
It expects the native backend and database to be available. The isolated
mock database keeps its own volume.

## Fixture behavior

The TCP server supports the named DataHub rules in `operations.json`,
native password authentication (including proxy users), common GenQuery
reads, collection and file operations, and the password queries MDR uses.
Collection listings overlap the same project and file fixtures used by the
rules. Missing objects and unsupported requests return native iRODS errors.

The rule fixtures cover the Python rules labeled public in `irods-ruleset`,
the legacy native rules with an `irule_dummy` entry point, and the existing
MDR calls. Use `python-irodsclient` to execute them by name, as the
rule-wrapper does. This example uses an open SDK session.

```python
from irods.rule import Rule

reply = Rule(
    session,
    body='getCollectionAVU(*path, "title", *value, "", "false"); writeLine("stdout", *value);',
    params={"*path": '"/nlmumc/projects/P000000001"'},
    output="ruleExecOut",
).execute()
print(reply.MsParam_PI[0].inOutStruct.stdoutBuf.buf.rstrip(b"\0").decode().strip())
```

The mock is deterministic and has no catalog database. Writes acknowledge
success and discard data. Some SDK methods immediately stat the thing they
just created, so the mock supplies that response on the same connection.
Later reads and listings use the original fixtures. Change the fixture files
to change the dataset, then run `./rit.sh mock backend` to rebuild and reload.

The server implements fixture rules by name and a small GenQuery catalog.
An arbitrary iRODS rule program, arbitrary GenQuery joins, replication,
parallel transfers, federation, PAM and other server features require
additional implementation or a real iRODS server. Jira and Elasticsearch
are separate services and the native iRODS mock does not implement their
protocols. The mock stack supplies local HTTP fixtures for MDR's help-center
and ontology requests.

`fixtures/responses.json` holds the rule responses, users, paths and file
mapping. Read selectors match on identity and decoded arguments. The most
specific selector wins. Write rules return a preset success for every
authenticated fixture user, including on missing objects or invalid input
values. The other JSON and text files hold the sample
metadata and file contents. `fixtures/captured.json` contains read-only
reference output from a native development instance.

To capture another **running native** environment, switch MDR to it first
and then run the read-only capture script:

```sh
docker exec -i dev-mdr-1 python < mock-backend/capture.py > /tmp/irods-capture.json
```

## Verification

```sh
docker exec dev-mock-backend-1 python -m unittest test_backend test_native

# With the ruleset source available, also verify coverage and rule files:
docker run --rm --network dh_default \
  -e MOCK_HOST=mock-backend -e RULESET_ROOT=/rules \
  -v "$PWD/externals/irods-ruleset:/rules:ro" \
  -v dev_mock_irods_ca:/mock-ca:ro \
  dev-mock-backend python -m unittest test_backend test_native

# With mock MDR running:
docker cp mock-backend/. dev-mdr-1:/tmp/mdr-mock-tests/
docker exec dev-mdr-1 python -P /tmp/mdr-mock-tests/test_wrapper.py
docker exec dev-mdr-1 python -P /tmp/mdr-mock-tests/test_mdr.py
```

The standalone tests use ordinary `python-irodsclient` sessions over TCP
and TLS. The MDR tests use the regular Django settings and verify the
fixture database host before running. To verify Keycloak login in Chromium,
install Playwright/Chromium in a dev container and run
`node /tmp/mdr-mock-tests/smoke.cjs` inside MDR.
