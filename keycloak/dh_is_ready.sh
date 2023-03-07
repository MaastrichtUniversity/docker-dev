#!/bin/bash

set -euo pipefail

STATE_FILE="/var/run/dh_import_state"

state="READY"


# file must exist
if [[ ! -f "${STATE_FILE}" ]]; then
    state="NOT READY"
elif [[ "$(< ${STATE_FILE})" != "completed" ]]; then
    # file must hold value "completed"
    state="NOT READY"
fi

# TODO: We could also do something like this here. Although it's expensive and increases dependency on custom mock env..
#
#  id=$(/opt/jboss/keycloak/bin/kcadm.sh get users -r django -q username=auser | jq -r '.[].id')
#  auser_group_check=$(/opt/jboss/keycloak/bin/kcadm.sh get "users/${id}/groups" -r django | jq '[.[] | select(.name | contains("mumc.m4i-nanoscopy.@all"))] | length')
#
#  if [[ "$auser_group_check" -ne 1 ]]; then
#    state="NOT READY"
#  fi
#


# return value (print)
echo "$state"

# return value (0 means success: it is ready)
if [[ "$state" == "NOT READY" ]]; then
    exit 1
else
    exit 0
fi
