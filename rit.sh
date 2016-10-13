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
        docker exec corpus_pacman_1 drush create-project-collection p.vanschayck@${domain} P000000005
    done

    for i in {1..4}; do
        docker exec corpus_pacman_1 drush create-project-collection m.coonen@${domain} P000000001
        docker exec corpus_pacman_1 drush create-project-collection m.coonen@${domain} P000000002
        docker exec corpus_pacman_1 drush create-project-collection d.theunissen@${domain} P000000001
        docker exec corpus_pacman_1 drush create-project-collection d.theunissen@${domain} P000000002
    done

    exit 0
fi

externals="externals/channels ssh://git@fhml-srv027.unimaas.nl:7999/mirthc/channels.git
externals/cloudbrowser_module ssh://git@fhml-srv027.unimaas.nl:7999/ritdev/cloudbrowser_module.git
externals/fhml_um_theme_demo ssh://git@fhml-srv027.unimaas.nl:7999/ritdev/fhml_um_theme_demo.git
externals/handsontable git@github.com:MaastrichtUniversity/handsontable.git
externals/irods-helper-cmd git@github.com:MaastrichtUniversity/irods-helper-cmd.git
externals/irods-microservices git@github.com:MaastrichtUniversity/irods-microservices.git
externals/irods-ruleset git@github.com:MaastrichtUniversity/irods-ruleset.git
externals/islandora_ontology_autocomplete git@github.com:MaastrichtUniversity/islandora_ontology_autocomplete.git
externals/rit_faker git@github.com:MaastrichtUniversity/rit_faker.git
externals/rit_forms git@github.com:MaastrichtUniversity/rit_forms.git
externals/rit-pacman git@github.com:MaastrichtUniversity/rit-pacman.git"

if [[ $1 == "externals" ]]; then
    mkdir -p externals

    if [[ $2 == "clone" ]]; then
        # Ignore error during cloning, as we don't care about existing dirs
        set +e
        while read -r external; do
            external=($external)
            echo -e "\e[32m =============== ${external[0]} ======================\033[0m"
            git clone ${external[1]} ${external[0]}
        done <<< "$externals"
    fi

    if [[ $2 == "status" ]]; then
        while read -r external; do
            external=($external)
            echo -e "\e[32m =============== ${external[0]} ======================\033[0m"
            git -C ${external[0]} status
        done <<< "$externals"
    fi

    if [[ $2 == "pull" ]]; then
        while read -r external; do
            external=($external)
            echo -e "\e[32m =============== ${external[0]} ======================\033[0m"
            git -C ${external[0]} pull --rebase
        done <<< "$externals"
    fi
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
