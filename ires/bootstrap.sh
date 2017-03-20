#!/bin/bash

set -e

source /etc/secrets

# Update RIT rules
# This does not work when a 2nd ires server exists, since both ires servers are executing 'make install' at the same source files at the same time
# TODO: Fix this for both ruleset and microservices
cd /rules && make install

# Update RIT microservices
# TODO: rewrite Make-procedure OR switch to CMake (just like iRODS-developers)
#cd /microservices && make install

# Update RIT helpers
cp /helpers/* /var/lib/irods/msiExecCmd_bin/.

# Mount ingest zones and rawdata
mkdir -p /mnt/ingest/zones
mkdir -p /mnt/ingest/shares/rawData
mount -t cifs ${INGEST_MOUNT} /mnt/ingest/zones -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=999,gid=999
mount -t cifs ${INGEST_MOUNT}/rawData /mnt/ingest/shares/rawData -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=999,gid=999

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "16s/.*/$RODS_PASSWORD/" /opt/irods/setup_responses
    fi

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /opt/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resource vaults (i.e. dummy-mounts in development)
    mkdir /mnt/UM-hnas-4k
    chown irods:irods /mnt/UM-hnas-4k
    mkdir /mnt/UM-hnas-4k-repl
    chown irods:irods /mnt/UM-hnas-4k-repl

    mkdir /mnt/AZM-storage
    chown irods:irods /mnt/AZM-storage
    mkdir /mnt/AZM-storage-repl
    chown irods:irods /mnt/AZM-storage-repl


    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed
else
    service irods start
fi

# Force start of Metalnx RMD
service rmd restart

#logstash
/etc/init.d/filebeat start

# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*