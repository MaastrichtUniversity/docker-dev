#!/usr/bin/env bash

if [[ $1 == "build" ]]; then
    docker build -t irods-icommand irods-icommands/
else
    docker run --rm -it -v `pwd`/../irods-ruleset:/home/irods/rules --link dockerdev_irods_1:irods.local irods-icommand "$@"
fi