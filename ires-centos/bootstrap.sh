#!/bin/bash

set -e

source /etc/secrets

# Update RIT rules
# FYI: This step (and make of the microservices) rely on sequential starts of the ires-containers. If those containers
# start simultaneously, the make steps fail because they are accessing the same files at the same time.
# Now solved by letting ires_centos wait for ires:1248 in Dockerize
cd /rules && make install

# Update RIT microservices
cd /microservices && make install

# Update RIT helpers
cp /helpers/* /var/lib/irods/iRODS/server/bin/cmd/.

# Mount ingest zones and rawdata
mkdir -p /mnt/ingest/zones
mount -t cifs ${INGEST_MOUNT} /mnt/ingest/zones -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=998,gid=997

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "17s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up iRODS
    /opt/irods/config.sh /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_MDL_EXPORT_CHANNEL}

    # Dirty temp.password workaround (TODO: NEEDS TO BE FIXED PROPERLY)
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

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

# TODO: Find solution for starting services in CentOS container (D-BUS errors): https://github.com/docker/docker/issues/7459
# Force start of Metalnx RMD
# service rmd restart

#logstash
#/etc/init.d/filebeat start

# this script must end with a persistent foreground process
tail -F /var/lib/irods/iRODS/server/log/rodsLog.*
