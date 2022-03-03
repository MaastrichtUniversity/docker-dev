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

From `irods-base` we build `icat-based`, `ires-based`, `ires-centos-based` and `ires-s3-based`.


## Build

:construction: **This way of building and running is temporary, final process will be different.** :construction:

```
$ ./build.sh
```
This will build `irods-base`, then `icat-based` and `ires-based`... etc. Edit that script at will.

## Run

:construction: **This way of running is temporary, final process will be different.** :construction:
```
$ cd ..   # root of docker-dev
$ docker-compose -f docker-compose.yml -f docker-compose-irods.yml up -d icat-based ires-based
```

## Images directory structure

Most images follow the following scheme:
* `config/`: Configuration files, settings, non-executables ...etc.
* `scripts/`: Scripts mostly used during boot up.
* `patch/`: Executable files that overwrite default ones in the image, or `.patch` files that we apply ourselves.
* `test-dev-ssl-certs/`: TLS certificates

