#!/usr/bin/env bash

# source library lib-dh.sh
if [[ -z $DH_ENV_HOME ]]; then
    DH_ENV_HOME=".."
    echo "(DH_ENV_HOME not set, using parent folder as default)"
fi
. $DH_ENV_HOME/lib-dh.sh

# Set logging level based on -v (--verbose) or -vv param
ARGS="$@ "
if [[ ${ARGS} = *"-vv "* ]]; then
   export LOGTRESHOLD=$DBG
   ARGS="${ARGS/-vv /}"
elif [[ ${ARGS} = *"--verbose "* ]] || [[ ${ARGS} = *"-v "* ]]; then
   export LOGTRESHOLD=$INF
   ARGS="${ARGS/--verbose /}"
   ARGS="${ARGS/-v /}"
fi

# Set the prefix for the project
COMPOSE_PROJECT_NAME="corpus"
export COMPOSE_PROJECT_NAME

set -e


# specify externals for this project
externals="externals/channels ssh://git@bitbucket.rit.unimaas.nl:7999/mirthc/channels.git
externals/alerts ssh://git@bitbucket.rit.unimaas.nl:7999/mirthc/alerts.git
externals/datahub_drupal_theme https://github.com/MaastrichtUniversity/datahub_drupal_theme.git
externals/handsontable https://github.com/MaastrichtUniversity/handsontable.git
externals/irods-helper-cmd https://github.com/MaastrichtUniversity/irods-helper-cmd.git
externals/irods-microservices https://github.com/MaastrichtUniversity/irods-microservices.git
externals/irods-ruleset https://github.com/MaastrichtUniversity/irods-ruleset.git
externals/islandora_ontology_autocomplete https://github.com/MaastrichtUniversity/islandora_ontology_autocomplete.git
externals/islandora_crossref_lookup https://github.com/MaastrichtUniversity/islandora_crossref_lookup.git
externals/rit_faker https://github.com/MaastrichtUniversity/rit_faker.git
externals/rit_forms https://github.com/MaastrichtUniversity/rit_forms.git
externals/rit-pacman https://github.com/MaastrichtUniversity/rit-pacman.git
externals/rit_landing_page https://github.com/MaastrichtUniversity/rit_landing_page.git
externals/irods-frontend https://github.com/MaastrichtUniversity/irods-frontend.git
externals/rit-metalnx-web https://github.com/MaastrichtUniversity/rit-metalnx-web.git
externals/rit-davrods https://github.com/MaastrichtUniversity/rit-davrods.git
externals/crossref-lookup https://github.com/MaastrichtUniversity/crossref-lookup.git
externals/epicpid-microservice https://github.com/MaastrichtUniversity/epicpid-microservice.git
externals/dh-rdm-service-docker https://github.com/MaastrichtUniversity/dh-rdm-service-docker.git
externals/mirthconnect-docker https://github.com/MaastrichtUniversity/mirthconnect-docker.git
externals/irods-open-access-repo https://github.com/MaastrichtUniversity/irods-open-access-repo.git
externals/sram-sync https://github.com/MaastrichtUniversity/sram-sync.git"


# do the required action in case of externals or exec
if [[ $1 == "externals" ]]; then
    action=${ARGS/$1/}
    run_repo_action ${action} "${externals}"
    exit 0
fi

if [[ $1 == "exec" ]]; then
    run_docker_exec ${COMPOSE_PROJECT_NAME} $2
    exit 0
fi


#
# code block for create functionality
#
domain="maastrichtuniversity.nl"

if [[ $1 == "create-ingest-zones" ]]; then
    ## Create initial dummy ingest-zones
    for i in {1..4}; do
        docker exec corpus_pacman_1 drush create-ingest-zone p.vanschayck@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone m.coonen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone d.theunissen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone p.suppers@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone r.brecheisen@${domain}
        docker exec corpus_pacman_1 drush create-ingest-zone jonathan.melius@${domain}
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
        docker exec corpus_pacman_1 drush create-project-collection jonathan.melius@${domain} P000000003
        echo "In P000000004"
        docker exec corpus_pacman_1 drush create-project-collection m.coonen@${domain} P000000004
        docker exec corpus_pacman_1 drush create-project-collection d.theunissen@${domain} P000000004
        docker exec corpus_pacman_1 drush create-project-collection jonathan.melius@${domain} P000000004
    done

    exit 0
fi

if [[ $1 == "login" ]]; then
    source './.env'
    docker login $ENV_REGISTRY_HOST
    exit 0
fi

# set RIT_ENV if not set already
env_selector


# Assuming docker-compose is available in the PATH
log $DBG "$0 [docker-compose \"$ARGS\"]"
docker-compose $ARGS


