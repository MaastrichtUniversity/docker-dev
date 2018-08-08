#!/bin/bash

set -e

source /etc/secrets

# Update RIT rules
# FYI: This step (and make of the microservices) rely on sequential starts of the ires-containers. If those containers
# start simultaneously, the make steps fail because they are accessing the same files at the same time.
# Now solved by letting ires_centos wait for ires:1248 in Dockerize
cd /rules && make install

# Remove previous build dir (if exists)
if [ -d "/microservices/build" ]; then
  rm -fr /microservices/build
fi

# Update RIT microservices
mkdir -p /microservices/build && cd /microservices/build && cmake .. && make && make install

# Update RIT helpers
cp /helpers/* /var/lib/irods/msiExecCmd_bin/.

# Mount ingest zones and rawdata
mkdir -p /mnt/ingest/zones
mount -t cifs ${INGEST_MOUNT} /mnt/ingest/zones -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=998,gid=997,vers=1.0

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "16s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_MDL_EXPORT_CHANNEL ${MIRTH_MDL_EXPORT_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resource vaults (i.e. dummy-mounts in development)
    mkdir /mnt/AZM-storage
    chown irods:irods /mnt/AZM-storage
    mkdir /mnt/AZM-storage-repl
    chown irods:irods /mnt/AZM-storage-repl


    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed

    # Force restart of irods service (see iRODS 4.1.10 bug described in RITDEV-231)
    # TODO: Determine if this restart is still required in iRODS 4.2.3
    #service irods restart
else
    service irods start
fi

# Copy the service-control scripts outside of /etc/init.d folder to prevent D-Bus kicking in & force the service to start
# Metalnx RMD
cp /etc/init.d/rmd /opt/rmd/rmd && /opt/rmd/rmd restart
# Logstash
cp /etc/init.d/filebeat /opt/filebeat && /opt/filebeat restart

# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*
