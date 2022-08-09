#!/bin/bash
# Healthcheck: Healthy if user 'auser' exists and belongs to group 'mumc.m4i-nanoscopy.@all'
# Warning: THIS CHECK IS EXPENSIVE!

ret_val=0

id=$(/opt/jboss/keycloak/bin/kcadm.sh get users -r django -q username=auser | jq -r '.[].id')
auser_group_check=$(/opt/jboss/keycloak/bin/kcadm.sh get "users/${id}/groups" -r django | jq '[.[] | select(.name | contains("mumc.m4i-nanoscopy.@all"))] | length')

if [[ "$auser_group_check" -ne 1 ]]; then
    echo "Health check failed for keycloak. Does 'auser' exist and belong to group 'mumc.m4i-nanoscopy.@all'"
    exit 1
fi


exit $ret_val
