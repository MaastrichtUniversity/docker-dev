#!/bin/bash
# Temporary script to build (and only build) iRODS images

export RIT_ENV=dev

# This script is meant to be called from the directory where it lives and the
# docker-compose.yml is found.
cd "$(dirname "$BASH_SOURCE")"

images=(
    # pick and choose (by commenting lines in and out)
    irods-base-ubuntu
    irods-base-centos
    irods-icat
    irods-ires
    irods-ires-s3
    irods-ires-centos
)


for image in ${images[@]}; do
    echo
    echo "Building: $image"
    docker-compose build $@ $image
done
