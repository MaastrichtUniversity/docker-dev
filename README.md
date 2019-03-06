## Prep

* Specify paths in the _.env_ file
```
VOLUMES_PATH=~/rados-support/docker-dev/volumes_data/ceph
DISKS_PATH=~/rados-support/docker-dev/volumes_data/disks

```

* Run bootstrap.sh to create blockdevices and clean old ceph-configs from previous run

## Get external repositories
```
cd docker-dev
git clone git@github.com:irods/irods_resource_plugin_rados externals/irods_resource_plugin_rados
```

## Run
```
./run_rit_light.sh build
./run_rit_light.sh up
```
