#!/usr/bin/env bash

# source library lib-dh.sh
if [[ -z $DH_ENV_HOME ]]; then
    DH_ENV_HOME=".."
#    echo "(DH_ENV_HOME not set, using parent folder as default)"
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
COMPOSE_PROJECT_NAME="dev"
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
externals/dh-irods https://github.com/MaastrichtUniversity/dh-irods.git
externals/dh-python-irods-utils https://github.com/MaastrichtUniversity/dh-python-irods-utils.git
externals/cedar-parsing-utils https://github.com/MaastrichtUniversity/cedar-parsing-utils.git
externals/dh-elasticsearch https://github.com/MaastrichtUniversity/dh-elasticsearch.git
externals/dh-help-center https://github.com/MaastrichtUniversity/dh-help-center.git
externals/dh-admin-tools https://github.com/MaastrichtUniversity/dh-admin-tools"

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

if [[ $1 == "make" ]]; then
   if [[ $2 == "rules" ]]; then
      set +e
      docker exec -u irods ${COMPOSE_PROJECT_NAME}-icat-1 make -C /rules
      docker exec -u irods ${COMPOSE_PROJECT_NAME}-ires-hnas-um-1 make -C /rules
      docker exec -u irods ${COMPOSE_PROJECT_NAME}-ires-hnas-azm-1 make -C /rules
      docker exec -u irods ${COMPOSE_PROJECT_NAME}-ires-ceph-gl-1 make -C /rules
      docker exec -u irods ${COMPOSE_PROJECT_NAME}-ires-ceph-ac-1 make -C /rules
      exit 0
   fi
   if [[ $2 == "microservices" ]]; then
      set +e
      docker exec -it ${COMPOSE_PROJECT_NAME}-icat-1 sh -c "cmake /microservices/ && make -C /microservices/ && make install -C  /microservices/"
      docker exec -it ${COMPOSE_PROJECT_NAME}-ires-hnas-um-1 sh -c "cmake /microservices/ && make -C /microservices/ && make install -C  /microservices/"
      docker exec -it ${COMPOSE_PROJECT_NAME}-ires-hnas-azm-1 sh -c "cmake /microservices/ && make -C /microservices/ && make install -C  /microservices/"
      docker exec -it ${COMPOSE_PROJECT_NAME}-ires-ceph-gl-1 sh -c "cmake /microservices/ && make -C /microservices/ && make install -C  /microservices/"
      docker exec -it ${COMPOSE_PROJECT_NAME}-ires-ceph-ac-1 sh -c "cmake /microservices/ && make -C /microservices/ && make install -C  /microservices/"
      exit 0
   fi
fi

# Run test cases
# e.g:
# * irods
# ./rit.sh test irods . # to execute all tests in the folder '/rules/test_cases'
# ./rit.sh test irods test_policies.py # to execute the tests inside '/rules/test_cases/test_policies.py'
# ./rit.sh test irods test_policies.py::TestPolicies::test_post_proc_for_coll_create # to only execute a single test
# * mdr
# ./rit.sh test mdr # to execute all tests
# ./rit.sh test mdr app.tests.test_projects # to execute the tests inside '/app/tests/test_projects'
if [[ $1 == "test" ]]; then
   if [[ $2 == "irods" ]]; then
      set +e
      docker exec -it ${COMPOSE_PROJECT_NAME}-icat-1 su irods -c "cd /rules/test_cases && /var/lib/irods/.local/bin/pytest -v -p no:cacheprovider -k 'not Mounted' ${3}"
      docker exec -it ${COMPOSE_PROJECT_NAME}-ires-hnas-um-1 su irods -c "cd /rules/test_cases && /var/lib/irods/.local/bin/pytest -v -p no:cacheprovider  -k 'Mounted' ${3}"
      exit 0
   fi
   if [[ $2 == "mdr" ]]; then
      set +e
      docker exec -it ${COMPOSE_PROJECT_NAME}-mdr-1 su -c "python manage.py test ${3}"
      exit 0
   fi
fi


#
# code block for create functionality
#

# set RIT_ENV if not set already
env_selector

# faker actions
if [[ $1 == "faker" ]]; then
    shift 1
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal run --rm dh-faker python -u create_fake_data.py "$@"
    exit 0
fi

# Create docker network common_default if it does not exists
if [ ! $(docker network ls --filter name=common_default --format="true") ] ;
      then
       echo "Creating network common_default"
       docker network create common_default
fi

# Start minimal docker-dev environment
if [[ $1 == "minimal" ]]; then
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal up -d
    # TODO: we could have a function for: "docker compose -f docker-compose.yml -f docker-compose-irods.yml", perhaps with exec.
    #       and another one for is_ready (not just the convenience thing
    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec icat /dh_is_ready.sh;
    do
      echo "Waiting for iCAT"
      sleep 10
    done

    echo "iCAT is Done"

    echo "Upping ires-hnas-um now.."
    ./rit.sh up -d ires-hnas-um

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec keycloak /dh_is_ready.sh;
    do
      echo "Waiting for keycloak"
      sleep 20
    done

    echo "Keycloak is Done"

    echo "Running single run of SRAM-SYNC"
    ./rit.sh up -d sram-sync

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec sram-sync /dh_is_ready.sh;
    do
      echo "Waiting for sram-sync"
      sleep 5
    done

    ./rit.sh stop sram-sync

    exit 0
fi

# for now same style as minimal, although this all could use a proper refactor!
if [[ "$1" == "backend" ]]; then
    # Quick PoC: FIXME! Refactor me! This code below is more of a functional "note" than code.
    # Modifications to the docker-compose profiles are completely not thought out! Just trying thing out here.
    #
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal up -d
    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec icat /dh_is_ready.sh;
    do
      echo "Waiting for iCAT, sleeping 10"
      sleep 10
    done
    echo "iCAT is Done."

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec keycloak /dh_is_ready.sh;
    do
      echo "Waiting for keycloak, sleeping 20"
      sleep 20
    done

    echo "Keycloak is Done"

    echo "Running single run of SRAM-SYNC"
    ./rit.sh up -d sram-sync

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec sram-sync /dh_is_ready.sh;
    do
      echo "Waiting for sram-sync, sleeping 5"
      sleep 5
    done

    ./rit.sh stop sram-sync

    echo "Starting backend-after-icat (iRES's)"
    # we bring up all ires's (or anything that depends on iCAT being up)
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend-after-icat up -d

    # We also could do something like:
    # all_backend_services=$(docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend --profile backend-after-icat config --services)
    # But this doesn't work nicely & we don't have dh_is_ready.sh for minio for example
    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec ires-hnas-um /dh_is_ready.sh;
    do
      echo "Waiting for ires-hnas-um, sleeping 10"
      sleep 10
    done

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec ires-hnas-azm /dh_is_ready.sh;
    do
      echo "Waiting for ires-hnas-azm, sleeping 5"
      sleep 5
    done

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec ires-ceph-ac /dh_is_ready.sh;
    do
      echo "Waiting for ires-ceph-gl, sleeping 5"
      sleep 5
    done

    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec ires-ceph-gl /dh_is_ready.sh;
    do
      echo "Waiting for ires-ceph-ac, sleeping 5"
      sleep 5
    done

    exit 0
fi

if [[ $1 == "login" ]]; then
    source './.env'
    docker login $ENV_REGISTRY_HOST
    exit 0
fi

# FIXME: Just for quick convenience for now
if [[ "$1" == "is_ready" ]]; then
    docker compose -f docker-compose.yml -f docker-compose-irods.yml exec "$2" /dh_is_ready.sh
    exit $?
fi

# Concatenate the .env file together with the irods.secrets.cfg
cat .env > .env_with_secrets
cat irods.secrets.cfg >> .env_with_secrets

# Assuming docker-compose is available in the PATH
log $DBG "$0 [docker compose \"$ARGS\"]"

docker compose --env-file .env_with_secrets -f docker-compose.yml -f docker-compose-irods.yml --profile full $ARGS

