## Config
Add irods.secrets.cfg

## Run
```
docker-compose build
docker-compose down
docker-compose up
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

You can also execute commands from the irods-ruleset repository like this:
```
./i [user] irule -F rules/list-projects.r
```


