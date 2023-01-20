#!/bin/bash

source /opt/irods/lib/irods.sh

echo "INFO: Applying setup_irods_already_installed_dev.patch to setup_irods.py"
echo "INFO: This patch will mkresc if the resource is not already registered and comment out test_put()"
patch_setup_irods /opt/irods/patch/setup_irods_already_installed_dev.patch

# Create fake HNAS (nothing real is volume mapped in development)
echo "INFO: Creating fake physical resource for HNAS at /mnt/${ENV_IRODS_STOR_RESC_NAME} and /mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
mkdir -p "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
chown irods:irods "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
mkdir -p "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
chown irods:irods "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"

echo "INFO: mocking irods-pre-ingest mount"
# Create the pre-ingest directory
mkdir -p /var/log/irods-pre-ingest
chown irods:irods /var/log/irods-pre-ingest

echo "INFO: mocking ingest zones: /mnt/ingest/zones (mounted), and /mnt/stagingResc01 (direct)"
mkdir -p /mnt/ingest/zones
mkdir -p /mnt/stagingResc01
chown irods:irods /mnt/ingest/zones
chown irods:irods /mnt/stagingResc01
