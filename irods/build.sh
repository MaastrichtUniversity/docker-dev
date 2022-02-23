#!/bin/bash

export RIT_ENV=dev

# This script is meant to be called from the directory where it lives and the
# docker-compose.yml is found.
cd "$(dirname "$BASH_SOURCE")"

# We first build the irods-base image
#docker-compose build $@ irods-base-ubuntu irods-icat
docker-compose build $@ irods-base-ubuntu irods-icat irods-ires

# Then icat, ires, ires-s3, ires-centos
