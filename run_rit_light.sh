#!/usr/bin/env bash

# Set the prefix for the project
COMPOSE_PROJECT_NAME="corpus"
export COMPOSE_PROJECT_NAME

set -e


RIT_ENV="support"
export RIT_ENV

# Load versions ENV vars
source set_versions_env.sh

# Assuming docker-compose is available in the PATH
docker-compose $@


