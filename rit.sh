#!/usr/bin/env bash
# Set the prefix for the project
COMPOSE_PROJECT_NAME="corpus"
export COMPOSE_PROJECT_NAME

set -e

domain="maastrichtuniversity.nl"

if [[ $1 == "create-ingest-zones" ]]; then
    ## Create initial dummy ingest-zones
    for i in {1..4}; do
        docker exec corpus_pacman_1 drush create-ingest-zone p.vanschayck@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone m.coonen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone d.theunissen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone p.suppers@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone r.niesten@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone r.brecheisen@${domain}
    done

    exit 0
fi

if [[ $1 == "create-project-collections" ]]; then
    ## Create dummy project collections
    for i in {1..4}; do
        echo "In P000000001"
        docker exec corpus_pacman_1 drush create-project-collection p.vanschayck@${domain} P000000001
    done

    for i in {1..4}; do
        echo "In P000000003"
        docker exec corpus_pacman_1 drush create-project-collection m.coonen@${domain} P000000003
        docker exec corpus_pacman_1 drush create-project-collection d.theunissen@${domain} P000000003
        docker exec corpus_pacman_1 drush create-project-collection r.niesten@${domain} P000000003
        echo "In P000000004"
        docker exec corpus_pacman_1 drush create-project-collection m.coonen@${domain} P000000004
        docker exec corpus_pacman_1 drush create-project-collection d.theunissen@${domain} P000000004
        docker exec corpus_pacman_1 drush create-project-collection r.niesten@${domain} P000000004
    done

    exit 0
fi

externals="externals/channels ssh://git@bitbucket.rit.unimaas.nl:7999/mirthc/channels.git
externals/alerts ssh://git@bitbucket.rit.unimaas.nl:7999/mirthc/alerts.git
externals/fhml_um_theme_demo ssh://git@bitbucket.rit.unimaas.nl:7999/ritdev/fhml_um_theme_demo.git
externals/handsontable git@github.com:MaastrichtUniversity/handsontable.git
externals/irods-helper-cmd git@github.com:MaastrichtUniversity/irods-helper-cmd.git
externals/irods-microservices git@github.com:MaastrichtUniversity/irods-microservices.git
externals/irods-ruleset git@github.com:MaastrichtUniversity/irods-ruleset.git
externals/islandora_ontology_autocomplete git@github.com:MaastrichtUniversity/islandora_ontology_autocomplete.git
externals/islandora_crossref_lookup git@github.com:MaastrichtUniversity/islandora_crossref_lookup.git
externals/rit_faker git@github.com:MaastrichtUniversity/rit_faker.git
externals/rit_forms git@github.com:MaastrichtUniversity/rit_forms.git
externals/rit-pacman git@github.com:MaastrichtUniversity/rit-pacman.git
externals/rit_landing_page git@github.com:MaastrichtUniversity/rit_landing_page.git
externals/irods-frontend git@github.com:MaastrichtUniversity/irods-frontend.git
externals/rit-metalnx-web git@github.com:MaastrichtUniversity/rit-metalnx-web.git
externals/rit-davrods git@github.com:MaastrichtUniversity/rit-davrods.git
externals/crossref-lookup git@github.com:MaastrichtUniversity/crossref-lookup.git "

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

if [[ $1 == "exec" ]]; then
    echo "Connect to container instance : ${COMPOSE_PROJECT_NAME}_${2}_1"
    docker exec -it ${COMPOSE_PROJECT_NAME}_${2}_1 env COLUMNS=$(tput cols) LINES=$(tput lines) /bin/bash
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

    if [[ $HOSTNAME == "fhml-srv065" ]]; then
        RIT_ENV="dev3"
    fi

fi
export RIT_ENV

# Assuming docker-compose is available in the PATH
docker-compose "$@"
