## Config
* Add irods.secrets.cfg
```
INGEST_PASSWORD=
INGEST_USER=
INGEST_MOUNT=
INGEST_MIRTHACL_USER=
INGEST_MIRTHACL_PASSWORD=
INGEST_MIRTHACL_URL=
LDAP_PASSWORD=
```

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
**Note:** Please be aware that these containers depend on a running ``proxy`` container from [docker-common](https://github.com/MaastrichtUniversity/docker-common) in order to be accessible on their ``VIRTUAL_HOST`` address.

## Faker
Create fake ingest zones and project collections
```
./rit.sh create-ingest-zones
./rit.sh create-project-collections
```

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
