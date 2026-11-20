## Config
* Add _irods.secrets.cfg_ file
```
INGEST_PASSWORD=
INGEST_USER=
INGEST_MOUNT=
LDAP_PASSWORD=
LDAP_USER="CN=Rit-dev (DATAHUB),OU=Resources,OU=Users,OU=DATAHUB,OU=FHML,DC=unimaas,DC=nl"
LDAP_URL=ldap://ldap.maastrichtuniversity.nl
LDAP_DOMAIN=DC=unimaas,DC=nl
USE_SAMBA=false
BIOPORTAL_API_KEY=
ATLASSIAN_API_KEY=(ATLASSIAN_API_KEY)
ATLASSIAN_API_USERNAME=(ATLASSIAN_EMAIL)
REACT_APP_CAPTCHA_SECRET_KEY=(Google captcha API secret key)
REACT_APP_CAPTCHA_SITE_KEY=(Google captcha API public site key)
```

* Specify the default values and versions for environment vars in the _.env_ file
```
# iRODS and iRES
ENV_IRODS_VERSION=4.2.11-1~bionic
ENV_IRODS_PYTHON_PLUGIN_VERSION=4.2.11.1-1~bionic
ENV_IRODS_RESC_PLUGIN_S3_VERSION=4.2.11.2-1~bionic

<...>

# Other (used in various containers)
ENV_DOCKERIZE_VERSION=v0.2.0
ENV_FILEBEAT_VERSION=5.2.0

```


## Get external repositories
```
./rit.sh externals clone
```

## Run
```
./rit.sh build
./rit.sh down
./rit.sh up

# Special
./rit.sh build --no-cache
./rit.sh build --pull --no-cache     # Attempts to pull a newer version of the upstream base image
```
> **NOTE:** Please be aware that these containers depend on a running ``proxy`` container from [docker-common](https://github.com/MaastrichtUniversity/docker-common) in order to be accessible on their ``VIRTUAL_HOST`` address.

### Backend catalog seed

These commands require Python 3 on the host, using only its standard library.

```sh
./rit.sh backend
./rit.sh backend --fresh
./rit.sh backend --reset --fresh
./rit.sh seed rebuild
```

`backend` preserves an existing catalog. For an empty catalog, it restores the
default snapshot before starting iCAT and the resource servers. Local container
configuration, rules checks, Garage setup and SRAM synchronization still run.
Resource containers join the network early so iCAT can resolve the resource hosts
already in the snapshot; their entrypoint waits for `rit.sh` to release bootstrap
after iCAT is ready.

Fixed local proxy and mock resource hostname mappings are declared with
`extra_hosts` in the Compose files, so Docker maintains them across restarts.
Changes to these mappings require recreating the affected containers; restarting
an existing container keeps its previous Compose configuration. No catalog reset
or seed rebuild is needed for hostname-mapping changes.

Development iRODS images install the local `externals/irods-ruleset` checkout at
build time, using a named build context (Compose 2.17+ with BuildKit). Rebuild them
with `./rit.sh build icat ires-hnas-um`. Before starting iRODS, new and reused
containers compare the mounted `/rules` sources with the last successful rules
installation. Matching contents skip `make`; changed contents run a full rebuild,
including dependencies. Failed installations stop startup and leave no valid
fingerprint. Fingerprints cover Python/native sources, Makefiles and packaging
inputs, excluding generated rules, caches, tests and Git metadata.
`./rit.sh make rules` still forces installation and updates the fingerprint.
The shared `dh-irods` optimization can also be enabled for acc/prod builds using
`IRODS_BASE_STAGE=irods-rules` and a `ruleset` build context. It does not depend on
`ENV_ENVIRONMENT`; builds without preinstalled rules retain their existing behavior.

`--fresh` skips the snapshot and runs the normal bootstrap scripts to populate
an empty catalog. It refuses a populated catalog. `--reset` explicitly removes
the iRODS containers, catalog and Garage anonymous volumes before startup; it
also removes files in the containers' vaults. Other application databases and
host-mounted ingest directories are preserved. Use `backend --reset` to return
to the default snapshot, or add `--fresh` to regenerate fixtures through bootstrap.

`seed rebuild` generates a replacement snapshot using the normal bootstrap
scripts in a temporary Docker project. It uses separate networks, publishes no
ports and replaces host ingest mounts with temporary volumes. The temporary
containers and volumes are removed on exit. It requires the current iRODS and
Garage images to be built, and a recent Docker Compose supporting `!reset`.

The generated files live under `irods/irods-db/seed/`. The baseline contains nine
empty projects, users, groups, resources, metadata and permissions; it contains
development credentials and no stored data files. Rebuild it after changing
fixtures, users, configured versions or project/resource settings. The dump has a
checksum; `config.json` records the configuration used to generate it. A missing,
incompatible or damaged snapshot is an error on an empty catalog; use `--fresh`
or rebuild it. A populated catalog does not need a matching snapshot, but its own
creation configuration must match startup.

Every `backend` start checks the creation record stored alongside PostgreSQL's
data, including when the database container is stopped. The check runs before
Compose can replace the PostgreSQL image. It compares:

- Configured PostgreSQL, iRODS, Python/S3 plugin and Garage versions.
- User fixtures in `keycloak/users.json` and the development LDAP LDIF files.
- iRODS host/resource settings and the project/resource bootstrap recipes,
  configuration template and project creation rules.

Compose's resolved values are used, including environment overrides. Credentials
are hashed, and errors list the changed inputs without displaying their values.
Unrelated application settings and startup-only switches do not invalidate the
catalog. This checks initialization inputs; normal development changes made
inside iRODS do not invalidate the record.

A mismatch stops startup without deleting data. Either run `./rit.sh seed rebuild`
followed by `./rit.sh backend --reset`, or use `./rit.sh backend --reset --fresh`.
Seed compatibility is checked before `--reset` deletes anything. Legacy catalogs
without a creation record need one explicit reset. Interrupted fresh bootstrap
remains marked incomplete and also requires reset if it populated the catalog.

These checks and creation records apply only when iCAT's effective
`ENV_ENVIRONMENT` is `dev`. Acceptance and production startup in `dh-irods` is
unchanged; running the helper outside `dev` skips development checks and seeding.

The seed captures the bootstrap fixtures before SRAM synchronization. SRAM still
synchronizes against the development LDAP when `backend` starts. Direct Compose
commands and `./rit.sh minimal` retain their existing startup behavior.

Run the host-side seed regression tests without Docker:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s irods/irods-db -p 'test_*.py'
```


## Tab completion for ./rit.sh

Load the existing completion script once per terminal, from this directory.
For Bash:

```bash
source ./dhdev-completion.bash
```

For zsh, enable its Bash completion compatibility first (skip `compinit` if
your shell configuration already runs it):

```zsh
autoload -Uz compinit bashcompinit
compinit
bashcompinit
source ./dhdev-completion.bash
```

Then `./rit.sh ext<Tab>` completes to `./rit.sh externals`.
No installation or shell startup file changes are needed. Completion is loaded
into the current shell, so running `./rit.sh` alone cannot enable it.

## Advanced usage

### How to add a new version variable 'FOO' to the project?
1. Add this entry to _.env_ : ENV_FOO=bar
1. Add to _docker-compose.yml_ :
    ```
    # if required at build time
    servicename:
      build:
        args:
          ENV_FOO: ${ENV_FOO}

    # if required at run time
    servicename:
      environment:
        ENV_FOO: ${ENV_FOO}
    ```
1. (applies only to build time) Add to _servicename/Dockerfile_ :
    ```
    ARG ENV_FOO
    ```
1. Build the project as usual with `./rit.sh build`


### iRODS setup responses
Unattended installation of iRODS requires a 'setup_responses' file. 
This file is different for the iCAT-enabled-server and the iRODS-resource-server. 
The order of the elements is important!

*iCAT-enabled-server (or iCAT provider)*
```
1. IRODS_SERVICE_ACCOUNT_NAME
2. IRODS_SERVICE_ACCOUNT_GROUP
3. IRODS_SERVER_ROLE               # 1. provider, 2. consumer
4. ODBC_DRIVER_FOR_POSTGRES        # 1. PostgreSQL ANSI, 2. PostgreSQL Unicode
5. IRODS_DATABASE_SERVER_HOSTNAME
6. IRODS_DATABASE_SERVER_PORT
7. IRODS_DATABASE_NAME
8. IRODS_DATABASE_USER_NAME
9. CONFIRMATION_ANSWER (yes)
10. IRODS_DATABASE_PASSWORD
11. IRODS_DATABASE_USER_PASSWORD_SALT
12. IRODS_ZONE_NAME
13. IRODS_PORT
14. IRODS_PORT_RANGE_BEGIN
15. IRODS_PORT_RANGE_END
16. IRODS_CONTROL_PLANE_PORT
17. IRODS_SCHEMA_VALIDATION
18. IRODS_SERVER_ADMINISTRATOR_USER_NAME
19. CONFIRMATION_ANSWER (yes)
20. IRODS_SERVER_ZONE_KEY
21. IRODS_SERVER_NEGOTIATION_KEY
22. IRODS_CONTROL_PLANE_KEY
23. IRODS_SERVER_ADMINISTRATOR_PASSWORD
24. IRODS_VAULT_DIRECTORY
```

*iRODS-resource-server (or iCAT consumer)*
```
1. IRODS_SERVICE_ACCOUNT_NAME
2. IRODS_SERVICE_ACCOUNT_GROUP
3. IRODS_SERVER_ROLE               # 1. provider, 2. consumer
4. IRODS_ZONE_NAME
5. ICAT_PROVIDER_HOSTNAME
6. IRODS_PORT
7. IRODS_PORT_RANGE_BEGIN
8. IRODS_PORT_RANGE_END
9. IRODS_CONTROL_PLANE_PORT
10. IRODS_SCHEMA_VALIDATION
11. IRODS_SERVER_ADMINISTRATOR_USER_NAME
12. CONFIRMATION_ANSWER (yes)
13. IRODS_SERVER_ZONE_KEY
14. IRODS_SERVER_NEGOTIATION_KEY
15. IRODS_CONTROL_PLANE_KEY
16. IRODS_SERVER_ADMINISTRATOR_PASSWORD
17. IRODS_VAULT_DIRECTORY
```

## Faker
Create fake ingest zones and project collections
```
./rit.sh create-ingest-zones
./rit.sh create-project-collections
```

## dhdev
A copy version of rit.sh with auto-completion enabled
### Configuration
* dhdev-completion.bash
* dhdev-completion.config
```
# Create the configuration file if it doesn't exist yet
# 2 variables are expectes localBinDir & localBashrcDir
# cat dhdev-completion.config
localBinDir=~/.local/bin
localBashrcDir=~
```
### Installation
```
./rit.sh install dhdev
# or to update
dhdev install dhdev
```
### Usage
```
dhdev stack public build
dhdev stack public up
dhdev stack public logs
dhdev test help-center-backend test_process_html.py
dhdev externals status
```
