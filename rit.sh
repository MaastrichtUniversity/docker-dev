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
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_keycloak(){
    local deadline=$((SECONDS + 300)) status
    echo "Waiting for Keycloak initialization"
    while (( SECONDS < deadline )); do
      if timeout --foreground --kill-after=2s 5s docker compose -f docker-compose.yml -f docker-compose-irods.yml exec -T --interactive=false keycloak /dh_is_ready.sh < /dev/null; then
        return 0
      else
        status=$?
      fi
      case "$status" in 130|143) return "$status" ;; esac
      if [[ "$status" == 2 ]] || [[ "$(timeout --foreground --kill-after=2s 5s docker compose -f docker-compose.yml -f docker-compose-irods.yml ps -a --format '{{.State}}' keycloak < /dev/null)" == exited ]]; then
        break
      fi
      sleep 2
    done
    echo "ERROR: Keycloak initialization failed or did not finish within 300 seconds." >&2
    timeout --foreground --kill-after=2s 5s docker compose -f docker-compose.yml -f docker-compose-irods.yml logs --tail 40 keycloak < /dev/null >&2 || true
    return 1
}

run_minimal(){
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

    wait_for_keycloak

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
}

run_backend(){
    set -e
    local seed_mode=snapshot reset=false option service
    for option in "$@"; do
      case "$option" in
        --fresh) seed_mode=fresh ;;
        --reset) reset=true ;;
        *) echo "Unknown backend option: $option" >&2; return 2 ;;
      esac
    done
    if [[ "$reset" == true ]]; then
      if [[ "$seed_mode" == snapshot ]]; then
        bash ./irods/irods-db/seed.sh check-seed
      fi
      bash ./irods/irods-db/seed.sh reset
    fi
    bash ./irods/irods-db/seed.sh prepare "$seed_mode"

    # Registered resource hosts must resolve while iCAT opens the seeded catalog.
    # Start their containers now, but release their bootstrap only after iCAT is ready.
    export ENV_IRODS_WAIT_FOR_CATALOG=true
    docker compose -f docker-compose.yml -f docker-compose-irods.yml up -d ires-hnas-um ires-hnas-azm

      # Quick PoC: FIXME! Refactor me! This code below is more of a functional "note" than code.
    # Modifications to the docker-compose profiles are completely not thought out! Just trying thing out here.
    #
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend up -d
    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec icat /dh_is_ready.sh;
    do
      echo "Waiting for iCAT, sleeping 10"
      sleep 10
    done
    echo "iCAT is Done."

    for service in ires-hnas-um ires-hnas-azm; do
      echo "Releasing $service startup"
      if ! timeout --foreground --kill-after=2s 10s docker compose -f docker-compose.yml -f docker-compose-irods.yml exec -T --interactive=false "$service" touch /var/run/irods_catalog_ready < /dev/null; then
        echo "ERROR: Could not release $service startup." >&2
        return 1
      fi
    done

    wait_for_keycloak

    echo "Keycloak is Done"

    echo "Starting backend-after-icat (SRAM synchronization)"
    # Resource servers are already running; start the remaining dependent services.
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend-after-icat up -d

    echo "Running single run of SRAM-SYNC"
    until docker compose -f docker-compose.yml -f docker-compose-irods.yml exec sram-sync /dh_is_ready.sh;
    do
      echo "Waiting for sram-sync, sleeping 5"
      sleep 5
    done
    ./rit.sh stop sram-sync

    # We also could do something like:
    # all_backend_services=$(docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend --profile backend-after-icat config --services)
    # But this doesn't work nicely & we don't have dh_is_ready.sh for garage for example
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

    bash ./irods/irods-db/seed.sh complete

    exit 0
}


# specify externals for this project
externals="externals/irods-helper-cmd https://github.com/MaastrichtUniversity/irods-helper-cmd.git
externals/irods-ruleset https://github.com/MaastrichtUniversity/irods-ruleset.git
externals/rit-davrods https://github.com/MaastrichtUniversity/rit-davrods.git
externals/epicpid-microservice https://github.com/MaastrichtUniversity/epicpid-microservice.git
externals/dh-mdr https://github.com/MaastrichtUniversity/dh-mdr.git
externals/irods-rule-wrapper https://github.com/MaastrichtUniversity/irods-rule-wrapper.git
externals/sram-sync https://github.com/MaastrichtUniversity/sram-sync.git
externals/dh-faker https://github.com/MaastrichtUniversity/dh-faker.git
externals/dh-irods https://github.com/MaastrichtUniversity/dh-irods.git
externals/dh-python-irods-utils https://github.com/MaastrichtUniversity/dh-python-irods-utils.git
externals/cedar-parsing-utils https://github.com/MaastrichtUniversity/cedar-parsing-utils.git
externals/dh-elasticsearch https://github.com/MaastrichtUniversity/dh-elasticsearch.git
externals/dh-help-center https://github.com/MaastrichtUniversity/dh-help-center.git
externals/dh-admin-tools https://github.com/MaastrichtUniversity/dh-admin-tools
externals/dh-home https://github.com/MaastrichtUniversity/dh-home
externals/dh-mdr-home https://github.com/MaastrichtUniversity/dh-mdr-home"

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

if [[ $1 == "install" ]]; then
   if [[ $2 == "dhdev" ]]; then
      if test -f ./dhdev-completion.config ; then
        source ./dhdev-completion.config
      else
        echo "No configuration 'dhdev-completion.config' file found in '$(pwd)'"
        echo "Have a look at the README.md file"
        exit 1
      fi
      scriptName=dhdev-completion.bash
      if ! test -f ./dhdev-completion.bash ; then
        echo "No completion '${scriptName}' script found in '$(pwd)'"
        exit 1
      fi
      echo "Install dhdev with auto-completion to ${localBinDir}"
      install rit.sh ${localBinDir}/dhdev
      if grep -q ${scriptName} ${localBashrcDir}/.bashrc; then
        echo "Source ${scriptName} already exists in ${localBashrcDir}/.bashrc"
      else
        echo "Append $(pwd)/${scriptName} to ${localBashrcDir}/.bashrc"
        echo "source $(pwd)/${scriptName}" >> ${localBashrcDir}/.bashrc
      fi
      echo "Done. Start using it by OPENING a NEW terminal!"
      exit 0
   fi
fi


if [[ $1 == "make" ]]; then
   if [[ $2 == "rules" ]]; then
      set +e
      rules_status=0
      for service in icat ires-hnas-um ires-hnas-azm; do
         docker exec -u irods "${COMPOSE_PROJECT_NAME}-${service}-1" bash -c '
            if [[ "${IRODS_RULES_PREINSTALLED:-false}" == true ]]; then
               python3 /opt/irods/lib/install_rules.py /rules --force
            else
               make -C /rules
            fi
         ' || rules_status=$?
      done
      exit "$rules_status"
   fi
fi

# Run test cases
# e.g:
# * irods
# ./rit.sh test irods # to execute all tests in the folder '/rules/test_cases'
# ./rit.sh test irods test_policies.py # to execute the tests inside '/rules/test_cases/test_policies.py'
# ./rit.sh test irods test_policies.py::TestPolicies::test_post_proc_for_coll_create # to only execute a single test
# * mdr
# ./rit.sh test mdr # to execute all tests
# ./rit.sh test mdr app.tests.test_projects # to execute the tests inside '/app/tests/test_projects'
# * help-center-backend
# ./rit.sh test help-center-backend # to execute all tests
if [[ $1 == "test" ]]; then
   if [[ $2 == "irods" ]]; then
      shift 2
      workers=3
      test_selection=""
      while [[ $# -gt 0 ]]; do
         case "$1" in
            --parallel) shift ;; # Accepted for compatibility; parallel is the default.
            --workers)
               if [[ $# -lt 2 || ! $2 =~ ^(0|[1-9][0-9]*)$ ]]; then
                  echo "--workers requires a nonnegative integer" >&2
                  exit 2
               fi
               workers=$2
               shift 2
               ;;
            -*) echo "Unknown irods test option: $1" >&2; exit 2 ;;
            *)
               if [[ -n $test_selection ]]; then
                  echo "Specify one test file or node ID" >&2
                  exit 2
               fi
               test_selection=$1
               shift
               ;;
         esac
      done

      phases=(sequential)
      if [[ $workers != 0 ]]; then
         phases=(parallel sequential)
      fi
      tests_found=false
      for phase in "${phases[@]}"; do
         pytest_options=()
         if [[ $phase == parallel ]]; then
            pytest_options=(-n "$workers" --dist loadgroup -m parallel)
         elif [[ $workers != 0 ]]; then
            pytest_options=(-m "not parallel")
         fi
         status=0
         docker exec -t -u irods \
           -e STOP_INGEST_TEST_TYPE=direct \
           ${COMPOSE_PROJECT_NAME}-icat-1 \
           /var/lib/irods/.local/bin/pytest -v -p no:cacheprovider \
           "${pytest_options[@]}" "/rules/test_cases/${test_selection}" || status=$?
         case $status in
            0) tests_found=true ;;
            5) ;; # A file/node selection may belong entirely to the other phase.
            *) exit "$status" ;;
         esac
      done

      # Run mounted stop-ingest tests for the full suite or an explicit selection.
      if [[ -z $test_selection || $test_selection == test_stop_ingest.py* ]]; then
         status=0
         docker exec -t -u irods \
           -e STOP_INGEST_TEST_TYPE=mounted \
           ${COMPOSE_PROJECT_NAME}-ires-hnas-um-1 \
           /var/lib/irods/.local/bin/pytest -v -p no:cacheprovider \
           "/rules/test_cases/${test_selection:-test_stop_ingest.py}" || status=$?
         case $status in
            0) tests_found=true ;;
            5) ;;
            *) exit "$status" ;;
         esac
      fi
      if [[ $tests_found == false ]]; then
         exit 5
      fi
      exit 0
   fi
   if [[ $2 == "mdr" ]]; then
      set +e
      docker exec -it ${COMPOSE_PROJECT_NAME}-mdr-1 su -c "python manage.py test ${3}"
      exit 0
   fi
   if [[ $2 == "help-center-backend" ]]; then
      set +e
      docker exec -it ${COMPOSE_PROJECT_NAME}-help-center-backend-1 su -c "python -m pip install pytest && pytest tests/tests_confluence_documents/${3}"
      exit 0
   fi
fi


#
# code block for create functionality
#

# set RIT_ENV if not set already
env_selector

if [[ "$1" == "seed" ]]; then
    if [[ "${2:-}" != "rebuild" || $# -ne 2 ]]; then
        echo "Usage: ./rit.sh seed rebuild" >&2
        exit 2
    fi
    bash ./irods/irods-db/seed.sh rebuild
    exit $?
fi

# faker actions
if [[ $1 == "faker" ]]; then
    shift 1
    docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal run --rm dh-faker python -u create_fake_data.py "$@"
    exit 0
fi

# Create docker network if it does not exists
if [ ! $(docker network ls --filter name=dh_default --format="true") ] ;
      then
       echo "Creating network dh_default"
       docker network create dh_default --subnet "172.21.1.0/24" --label "com.docker.compose.project"="common" --label "com.docker.compose.network"="default"
fi

if [[ $1 == "stack" ]]; then
   if [[ $2 == "minimal" ]]; then
     if [[ $3 == "up" ]]; then
        run_minimal
     fi
     if [[ $3 == "down" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal --profile minimal-after-icat stop
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal --profile minimal-after-icat rm -f
        docker compose -f docker-compose.yml -f docker-compose-irods.yml stop sram-sync
        docker compose -f docker-compose.yml -f docker-compose-irods.yml rm -f sram-sync
     fi
     if [[ $3 == "build" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal --profile minimal-after-icat build
     fi
     if [[ $3 == "logs" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile minimal --profile minimal-after-icat logs -f
     fi
   fi
   if [[ $2 == "backend" ]]; then
      if [[ $3 == "up" ]]; then
        run_backend "${@:4}"
     fi
     if [[ $3 == "down" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend --profile backend-after-icat stop
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend --profile backend-after-icat rm -f
        docker compose -f docker-compose.yml -f docker-compose-irods.yml stop sram-sync
        docker compose -f docker-compose.yml -f docker-compose-irods.yml rm -f sram-sync
     fi
     if [[ $3 == "build" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend --profile backend-after-icat build
     fi
     if [[ $3 == "logs" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile backend --profile backend-after-icat logs -f
     fi
   fi
   if [[ $2 == "public" ]]; then
      if [[ $3 == "up" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile public up -d
        exit 0
      fi
      if [[ $3 == "down" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile public stop
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile public rm -f
        exit 0
      fi
      if [[ $3 == "build" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile public build
        exit 0
      fi
      if [[ $3 == "logs" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile public logs -f
        exit 0
      fi
   fi
   if [[ $2 == "admin" ]]; then
      if [[ $3 == "up" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile admin up -d
        exit 0
      fi
      if [[ $3 == "down" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile admin stop
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile admin rm -f
        exit 0
      fi
      if [[ $3 == "build" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile admin build
        exit 0
      fi
      if [[ $3 == "logs" ]]; then
        docker compose -f docker-compose.yml -f docker-compose-irods.yml --profile admin logs -f
        exit 0
      fi
   fi
   exit 0
fi

# Start minimal docker-dev environment
if [[ $1 == "minimal" ]]; then
    run_minimal
fi

# for now same style as minimal, although this all could use a proper refactor!
if [[ "$1" == "backend" ]]; then
  run_backend "${@:2}"
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
