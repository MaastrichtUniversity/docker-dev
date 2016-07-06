#!/usr/bin/env bash

set -e

if [[ $1 == "create-ingest-zones" ]]; then
    ## Create initial dummy ingest-zones
    for i in {1..4}; do
        docker exec dockerdev_pacman_1 drush create-ingest-zone p.vanschayck
        docker exec dockerdev_pacman_1 drush create-ingest-zone m.coonen
        docker exec dockerdev_pacman_1 drush create-ingest-zone d.theunissen
        docker exec dockerdev_pacman_1 drush create-ingest-zone p.suppers
    done

    exit 0
fi


if [[ -z $RIT_ENV ]]; then
    RIT_ENV="local"

    if [[ $HOSTNAME == "fhml-srv018" ]]; then
        RIT_ENV="acc"
    fi

    if [[ $HOSTNAME == "fhml-srv019" ]]; then
        RIT_ENV="dev1"
    fi

    if [[ $HOSTNAME == "fhml-srv020" ]]; then
        RIT_ENV="dev2"
    fi
fi

export RIT_ENV

# Assuming docker-compose is available in the PATH
docker-compose "$@"
