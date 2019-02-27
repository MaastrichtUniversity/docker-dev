## Config
* Add _irods.secrets.cfg_ file
```
INGEST_PASSWORD=
INGEST_USER=
INGEST_MOUNT=
INGEST_MIRTHACL_USER=
INGEST_MIRTHACL_PASSWORD=
INGEST_MIRTHACL_URL=
LDAP_PASSWORD=
```

* Specify the desired versions in the _set_version_env.sh_ file
```
# iRODS and iRES
ENV_IRODS_VERSION=4.2.4
ENV_IRODS_EXT_CLANG_VERSION=3.8-0
ENV_IRODS_EXT_CLANG_RUNTIME_VERSION=3.8-0
ENV_CMAKE_VERSION=3.12
ENV_CMAKE_LONG_VERSION=3.12.0

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


## Usage of the i command
First build the icommands image:
```
./i build
```
To execute a command:
```
./i [user] ils
```
Where `[user]` is a valid iRODS user as defined in irods/bootstrap_irods.sh. 
You can omit the domain, this is added automatically. 

You can also execute commands from the irods-ruleset repository like this:
```
./i [user] irule -F rules/projects/listContributingProjects.r 
./i [user] irule -F rules/projects/detailsProject.r "*project='P000000001'" "*inherited='false'"
./i [user] imeta add -C /nlmumc/ingest/zones/[collectionName] [attribute] [value] [unit]
etc..
```


## Advanced usage

### How to add a new version variable 'FOO' to the project?
1. Add this entry to _set_versions_env.sh_ : ENV_FOO=bar
1. Add to the bottom of _set_versions_env.sh_ : `export ENV_FOO`
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

