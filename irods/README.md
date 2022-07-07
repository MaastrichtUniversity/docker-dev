# iRODS development images

:construction: **Work in progress** :construction:

With these `Dockerfile`s, you should be able to build iRODS containers for use
in your development environment.

These are not meant for production. We have included in them more things than
are strictly necessary, things that might be useful during development or
debugging.


## Images structure
The base image is `irods-base`. This image limits itself to installing the
packages, utilities and other files necessary for a later installation of
iRODS. It doesn't define an entry point -- it's not a process. Therefore, it
shouldn't be used on its own to create a live container.

`irods-base` comes in two flavors: `ubuntu` and `centos`.

From `irods-base` we build `irods` (icat) , `ires`, `ires-centos` and `ires-s3`.


## Build

:construction: **This way of building and running is temporary, final process will be different.** :construction:

Unfortunately, you have to build the base images first, as `depends_on` is only
mean for running, not for building.

```
$ cd ..    # root of docker-dev
docker-dev$ ./rit.sh build irods-base-ubuntu irods-base-centos
docker-dev$ ./rit.sh build irods ires ires-s3-1 ires-centos
```
This will build `irods-base`s, then `irods` image, and `ires` image... etc.

The name of the images are:
* `${ENV_REGISTRY_HOST}/docker-dev/${ENV_BRANCH}/irods-base:ubuntu`
* `${ENV_REGISTRY_HOST}/docker-dev/${ENV_BRANCH}/irods-base:centos`


(following previous names)

## Run

:construction: **This way of running is temporary, final process will be different.** :construction:

```
$ cd ..   # root of docker-dev
docker-dev$ docker-compose -f docker-compose.yml -f docker-compose-irods.yml up -d irods ires
OR
docker-dev$ ./rit.sh up -d irods ires
```

## Images directory structure

Most images follow the following scheme:
* `config/`: Configuration files, settings, non-executables ...etc.
* `scripts/`: Scripts mostly used during boot up.
* `patch/`: Executable files that overwrite default ones in the image, or `.patch` files that we apply ourselves.
* `test-dev-ssl-certs/`: TLS certificates

