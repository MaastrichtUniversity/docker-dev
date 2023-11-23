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
