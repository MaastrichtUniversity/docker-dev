#!/usr/bin/env bash

set -e

domain="maastrichtuniversity.nl"

if [[ $1 == "create-ingest-zones" ]]; then
    ## Create initial dummy ingest-zones
    for i in {1..4}; do
        docker exec corpus_pacman_1 drush create-ingest-zone p.vanschayck@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone m.coonen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone d.theunissen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone p.suppers@${domain}
    done

    exit 0
fi

if [[ $1 == "create-project-collections" ]]; then
    ## Create dummy project collections
    for i in {1..4}; do
        docker exec corpus_pacman_1 drush create-project-collection p.vanschayck@${domain} MUMC-M4I-0000${i}
        docker exec corpus_pacman_1 drush create-project-collection m.coonen@${domain} MUMC-RIT-0000${i}
        docker exec corpus_pacman_1 drush create-project-collection d.theunissen@${domain} MUMC-RIT-0000${i}
        docker exec corpus_pacman_1 drush create-project-collection p.suppers@${domain} MUMC-RIT-0000${i}
    done

    exit 0
fi


if [[ -z $RIT_ENV ]]; then
    RIT_ENV="local"

    if [[ $HOSTNAME == "fhml-srv018" ]]; then
        RIT_ENV="tst"
    fi

    if [[ $HOSTNAME == "fhml-srv019" ]]; then
        RIT_ENV="dev1"
    fi

    if [[ $HOSTNAME == "fhml-srv020" ]]; then
        RIT_ENV="dev2"
    fi
fi
export RIT_ENV

# Set the prefix for the project
COMPOSE_PROJECT_NAME="corpus"
export COMPOSE_PROJECT_NAME

# Assuming docker-compose is available in the PATH
docker-compose "$@"
