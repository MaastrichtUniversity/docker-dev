#!/bin/bash
# This checks for signs of health in iCAT. Returns 0 if healthy.
#

# Supposed to be run by a configured irods user (i.e.
# $HOME/.irods/irods_environment.json has all the right values to run
# icommmands)

ret_val=0

# String we write in bootstrap_irods and expect to retrieve here.
check_string="Ability to retrive hopefully signifies good health."

# AVU check (proves ability to talk to iCAT)
health_avu=$(imeta ls -C /nlmumc/home/rods healthcheck | grep '^value')
if [[ ! "$health_avu" =~ "$check_string" ]]; then
    echo "ires: taling to icat failed: Could not retrieve the contents from AVU \"healtcheck\" in collection /nlmumc/home/rods that were expected."
    #echo $health_avu
    exit 1
fi

# Retrive file object in this-ires-provided resource:
health_file=$(iget /nlmumc/home/rods/.healthcheck_replRescUM01 -)
if [[ ! "$health_file" =~ "$check_string" ]]; then
    echo "Could not retrieve the contents fomr file /nlmumc/home/rods/.healthcheck_replRescUM01 in ires that were expected."
    #echo $health_file
    exit 1
fi

exit $ret_val
