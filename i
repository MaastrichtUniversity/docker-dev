#!/usr/bin/env bash

# Load versions ENV vars
source .env

if [[ $1 == "build" ]]; then
    docker build -t irods-icommand --build-arg ENV_IRODS_VERSION=${ENV_IRODS_VERSION} irods-icommands/
else
    docker run --rm -it -v `pwd`/externals/irods-ruleset:/home/irods/rules --net dev_default --link irods:irods.local irods-icommand "$@"
fi
