#!/bin/bash
# docker-dev's definition of iRODS being ready

set -euo pipefail

# we expect to be irods in this script
# might as well just check if we are root (0)...
if [[ "$(id -u)" != "${ENV_IRODS_UID:-$(id -u irods)}" ]]; then
    su irods -c $(realpath $0)
    exit $?
fi


state="READY"

# dh-irods must think it's ready
dh_irods_ready=$(/opt/irods/is_ready.sh) || { state="NOT READY"; }
# we could just do:  /opt/irods/scripts/is_ready.sh || { state="NOT READY"; }
if [[ "$dh_irods_ready" == "NOT READY" ]]; then
    state="NOT READY"
fi


# On top of dh-irods being ready, in dev we have other requirements for iCAT to be ready
dev_mockup_state=$(imeta ls -R rootResc bootstrap_irods_dev_mockup | grep -Po '(value: \K.*)' || true)
if [[ ! "$dev_mockup_state" =~ "complete" ]]; then
    state="NOT READY"
fi


# return value (print)
echo "$state"

# return value (0 means success: it is ready)
if [[ "$state" == "NOT READY" ]]; then
    exit 1
else
    exit 0
fi
