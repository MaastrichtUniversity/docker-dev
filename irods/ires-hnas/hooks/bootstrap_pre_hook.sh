#!/bin/bash

# NOTE: At the moment, every restart, this will be called! So make sure that these hooks are idempotent.
#       We could leverage irods_startup_state_get() here, but for now we leave like this..

# Create fake HNAS (nothing real is volume mapped in development)
if [[ ! -d "/mnt/${ENV_IRODS_STOR_RESC_NAME}" ]]; then
    mkdir -p "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
    chown irods:irods "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
    mkdir -p "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
    chown irods:irods "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
    echo "INFO: Creating fake physical resource for HNAS at /mnt/${ENV_IRODS_STOR_RESC_NAME}"
else
    echo "INFO: HNAS physical resource at /mnt/${ENV_IRODS_STOR_RESC_NAME} already exists."
fi

