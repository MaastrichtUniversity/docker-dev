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

# Create docker network common_default if it does not exists
if [ ! $(docker network ls --filter name=common_default --format="true") ] ;
      then
       echo "Creating network common_default"
       docker network create common_default
fi

# Check if base image are needed for a command
ubuntu_irods=(irods ires ires-s3-1 ires-s3-2)

if [[ $1 == "build" || $1 == "up" ]]; then
  for  item1 in "$@"; do
    for item2 in "${ubuntu_irods[@]}"; do

      if [[ $item1 == $item2 ]]; then
            if [ ! $(docker image ls registry.dh.unimaas.nl/docker-dev/master/irods-base:ubuntu --format="true") ] ;
              then
                echo "iRODS Ubuntu base does not exist, building"
                docker-compose -f docker-compose.yml -f docker-compose-irods.yml build irods-base-ubuntu
                break
            fi
      fi
    done
     if [[ $item1 == "ires-centos" ]]; then
            if [ ! $(docker image ls registry.dh.unimaas.nl/docker-dev/master/irods-base:centos --format="true") ] ;
              then
                echo "iRODS Centos base does not exist, building"
                docker-compose -f docker-compose.yml -f docker-compose-irods.yml build irods-base-centos
                break
            fi
      fi
  done
fi

# Assuming docker-compose is available in the PATH
log $DBG "$0 [docker-compose \"$ARGS\"]"
docker-compose -f docker-compose.yml -f docker-compose-irods.yml $ARGS


