#!/bin/bash

export RIT_ENV=dev

# This script is meant to be called from the directory where it lives and the
# docker-compose.yml is found.
cd "$(dirname "$BASH_SOURCE")"

# We first build the irods-base image
#docker-compose build $@ irods-base-ubuntu irods-icat
#docker-compose build $@

for image in irods-base-ubuntu irods-icat irods-ires irods-ires-s3; do
    echo
    echo "Building: $image"
    docker-compose build $@ $image
done

# Then icat, ires, ires-s3, ires-centos
