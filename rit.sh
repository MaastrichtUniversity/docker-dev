#!/usr/bin/env bash

if [[ -z $RIT_ENV ]]; then
    RIT_ENV="local"

    if [[ $HOSTNAME == "fhml-srv018" ]]; then
        RIT_ENV="acc"
    fi

    if [[ $HOSTNAME == "fhml-srv020" ]]; then
        RIT_ENV="dev1"
    fi

    if [[ $HOSTNAME == "fhml-srv021" ]]; then
        RIT_ENV="dev2"
    fi
fi

export RIT_ENV

# Assuming docker-compose is available in the PATH
docker-compose "$@"