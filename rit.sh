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
externals="externals/irods-helper-cmd https://github.com/MaastrichtUniversity/irods-helper-cmd.git
externals/irods-microservices https://github.com/MaastrichtUniversity/irods-microservices.git
externals/irods-ruleset https://github.com/MaastrichtUniversity/irods-ruleset.git
externals/irods-frontend https://github.com/MaastrichtUniversity/irods-frontend.git
externals/rit-davrods https://github.com/MaastrichtUniversity/rit-davrods.git
externals/epicpid-microservice https://github.com/MaastrichtUniversity/epicpid-microservice.git
externals/dh-mdr https://github.com/MaastrichtUniversity/dh-mdr.git
externals/irods-rule-wrapper https://github.com/MaastrichtUniversity/irods-rule-wrapper.git
externals/irods-open-access-repo https://github.com/MaastrichtUniversity/irods-open-access-repo.git
externals/sram-sync https://github.com/MaastrichtUniversity/sram-sync.git
externals/dh-faker https://github.com/MaastrichtUniversity/dh-faker.git
externals/dh-python-irods-utils https://github.com/MaastrichtUniversity/dh-python-irods-utils.git
externals/cedar-parsing-utils https://github.com/MaastrichtUniversity/cedar-parsing-utils.git"


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


