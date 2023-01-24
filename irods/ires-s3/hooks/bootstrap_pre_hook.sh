#!/bin/bash

source /opt/irods/lib/irods.sh

echo "INFO: Applying setup_irods_already_installed_dev.patch to setup_irods.py"
echo "INFO: This patch will mkresc if the resource is not already registered and comment out test_put()"
patch_setup_irods /opt/irods/patch/setup_irods_already_installed_dev.patch

# TODO! FIXME! Should this go here?
# ires-s3 is a very much a WIP still
mkdir -p /cache && chown irods /cache
