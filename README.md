## Config
* Add irods.secrets.cfg
```
INGEST_PASSWORD=
INGEST_USER=
INGEST_MOUNT=
INGEST_MIRTHACL_USER=
INGEST_MIRTHACL_PASSWORD=
INGEST_MIRTHACL_URL=
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
./i [user] irule -F rules/listContributingProjects.r
./i [user] irule -F rules/listManagingProjects.r
./i [user] irule -F rules/listViewingProjects.r
./i [user] irule -F rules/detailsProject.r "*project='MUMC-RIT-00013'"
./i [user] imeta add -C /nlmumc/ingestZone/[collectionName] [attribute] [value] [unit]
etc..
```
