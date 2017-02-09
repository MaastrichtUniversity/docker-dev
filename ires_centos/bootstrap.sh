#!/bin/bash

set -e

source /etc/secrets

# Update RIT helpers
cp /helpers/* /var/lib/irods/iRODS/server/bin/cmd/.

# Mount ingest zones and rawdata
mkdir -p /mnt/ingest/zones
mkdir -p /mnt/ingest/shares/rawData
mount -t cifs ${INGEST_MOUNT} /mnt/ingest/zones -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=998,gid=997
mount -t cifs ${INGEST_MOUNT}/rawData /mnt/ingest/shares/rawData -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=998,gid=997

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "17s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up iRODS
    /opt/irods/config.sh /etc/irods/setup_responses

    # Dirty temp.password workaround (TODO: NEEDS TO BE FIXED PROPERLY)
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 1200\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resource vaults (i.e. dummy-mounts in development)
    mkdir /mnt/AZM-storage
    chown irods:irods /mnt/AZM-storage
    mkdir /mnt/AZM-storage-repl
    chown irods:irods /mnt/AZM-storage-repl


#    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed
else
    service irods start
fi

# Force start of Metalnx RMD
# service rmd restart

# this script must end with a persistent foreground process
tail -F /var/lib/irods/iRODS/server/log/rodsLog.*
