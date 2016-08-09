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

if [[ $1 == "create-project-collections" ]]; then
    ## Create dummy project collections
    for i in {1..4}; do
        docker exec dockerdev_pacman_1 drush create-project-collection p.vanschayck MUMC-M4I-0000${i}
        docker exec dockerdev_pacman_1 drush create-project-collection m.coonen MUMC-RIT-0000${i}
        docker exec dockerdev_pacman_1 drush create-project-collection d.theunissen MUMC-RIT-0000${i}
        docker exec dockerdev_pacman_1 drush create-project-collection p.suppers MUMC-RIT-0000${i}
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

# Set other Docker Compose environment variables (mainly for pacman)
export IRODS_FRONTEND_ENV_VIRTUAL_HOST="frontend.$RIT_ENV.rit.unimaas.nl"
export IRODS_1_PORT_1247_TCP_ADDR="irods.$RIT_ENV.rit.unimaas.nl"
export IRODS_FRONTEND_1_PORT_80_TCP_ADDR="frontend.$RIT_ENV.rit.unimaas.nl"
export IRODS_ENV_RODS_PASSWORD="irods"


# Assuming docker-compose is available in the PATH
docker-compose "$@"
