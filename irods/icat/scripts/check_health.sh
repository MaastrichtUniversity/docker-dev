#!/bin/bash
# This checks for signs of health in iCAT. Returns 0 if healthy.
#

# Supposed to be run by a configured irods user (i.e.
# $HOME/.irods/irods_environment.json has all the right values to run
# icommmands)

ret_val=0

# String we write in bootstrap_irods and expect to retrieve here.
check_string="Ability to retrive hopefully signifies good health."

# AVU check:
health_avu=$(imeta ls -C /nlmumc/home/rods healthcheck | grep '^value')
if [[ ! "$health_avu" =~ "$check_string" ]]; then
    echo "Could not retrieve the contents from AVU \"healtcheck\" in collection /nlmumc/home/rods that were expected."
    #echo $health_avu
    exit 1
fi

# Retrive file object check:
health_file=$(iget /nlmumc/home/rods/.healthcheck -)
if [[ ! "$health_file" =~ "$check_string" ]]; then
    echo "Could not retrieve the contents fomr file /nlmumc/home/rods/.healthcheck in iCAT that were expected."
    #echo $health_file
    exit 1
fi

exit $ret_val
