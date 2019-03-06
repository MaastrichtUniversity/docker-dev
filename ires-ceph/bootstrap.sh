#!/bin/bash

set -e

source /etc/secrets

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "16s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    touch /var/run/irods_installed

else
    service irods start
fi

# Install iRODS librados plugin
echo "compiling iRODS rados plugin"
cd /irods_resource_plugin_rados && cmake -DCMAKE_INSTALL_PREFIX=/ . && make && make install

# Templating irados config file
touch /etc/irods/irados.config && chown irods: /etc/irods/irados.config && chmod 600 /etc/irods/irados.config
echo "[global]
    mon host = mon1" > /etc/irods/irados.config

echo "Waiting for irods-dev keyring to be created..."

while [ ! -f /etc/ceph/client.irods-dev.keyring ]
do
  sleep 1
done

cat /etc/ceph/client.irods-dev.keyring >> /etc/irods/irados.config

su - irods -c "iadmin mkresc radosResc irados ires-ceph:/tmp \"ceph|irods-dev|client.irods-dev\" "

# Create test files
cd /tmp
fallocate -l 5M 5MiB.bin
fallocate -l 50M 50MiB.bin


# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*
