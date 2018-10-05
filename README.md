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
