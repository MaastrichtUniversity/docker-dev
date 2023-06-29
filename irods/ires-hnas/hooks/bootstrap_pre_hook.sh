#!/bin/bash

source /opt/irods/lib/irods.sh

echo "INFO: Applying setup_irods_already_installed_dev.patch to setup_irods.py"
echo "INFO: This patch will mkresc if the resource is not already registered and comment out test_put()"
patch_setup_irods /opt/irods/patch/setup_irods_already_installed_dev.patch
mkdir -p /cache && chown irods /cache

# TODO: Nothing ever should be volume mapped here though, no?
if [[ ! -d "/mnt/${ENV_IRODS_STOR_RESC_NAME}" ]]; then
    # Create fake HNAS (nothing real is volume mapped in development)
    mkdir -p "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
    chown irods:irods "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
    mkdir -p "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
    chown irods:irods "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
    echo "INFO: Creating fake physical resource for HNAS at /mnt/${ENV_IRODS_STOR_RESC_NAME} and /mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
else
    echo "INFO: HNAS physical resource at /mnt/${ENV_IRODS_STOR_RESC_NAME} already exists."
fi

echo "INFO: mocking irods-pre-ingest mount"
# Create the pre-ingest directory
mkdir -p /var/log/irods-pre-ingest
chown irods:irods /var/log/irods-pre-ingest

if [[ ! -d "/mnt/ingest/zones" ]]; then
    echo "INFO: mocking ingest zone: /mnt/ingest/zones (mounted)"
    mkdir -p /mnt/ingest/zones
    chown irods:irods /mnt/ingest/zones
else
    echo "INFO: Found /mnt/ingest/zones, will not mock by creating now."
fi

if [[ ! -d "/mnt/stagingResc01" ]]; then
    # Temporary work-around due to not-nicely controlled difference between azm and um
    if [[ "${ENV_IRODS_STOR_RESC_NAME}" =~ "UM" ]]; then
        echo "INFO: ires-hnas contains \"UM\" in resource name. Assuming we want to mock direct ingest mount at /mnt/stagingResc01"
        mkdir -p /mnt/stagingResc01
        chown irods:irods /mnt/stagingResc01
    else
        echo "INFO: ires-hnas does not contain \"UM\" in resource name. Assuming we _don't_ want to mock direct ingest mount."
    fi
else
    echo "INFO: Found /mnt/stagingResc01, will not mock by creating now."
fi


# Hacky! This is to prevent the ires trying to resolve an address that it does not have access to, resulting in very poor performance in dev
# These values are fictive, the server in question cannot access the server anyway.
if [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "UM" ]]; then
    echo "172.0.0.1 ires-hnas-azm.dh.local" >> /etc/hosts
elif [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "AZM" ]]; then
    echo "172.0.0.1 ires-hnas-um.dh.local" >> /etc/hosts
    echo "172.0.0.2 ires-ceph-ac.dh.local" >> /etc/hosts
    echo "172.0.0.3 ires-ceph-gl.dh.local" >> /etc/hosts
fi
