#!/bin/bash

source /opt/irods/lib/irods.sh

echo "INFO: Applying setup_irods_already_installed_dev.patch to setup_irods.py"
echo "INFO: This patch will mkresc if the resource is not already registered and comment out test_put()"
patch_setup_irods /opt/irods/patch/setup_irods_already_installed_dev.patch
mkdir -p /cache && chown irods /cache

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

