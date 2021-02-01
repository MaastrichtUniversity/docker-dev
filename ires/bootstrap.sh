#!/bin/bash
sleep 10
set -e

source /etc/secrets

# Python requirements
pip install -r /rules/python/python_requirements.txt

# Update RIT rules
cd /rules && make

# Build RIT microservices
mkdir -p /tmp/microservices-build && \
    cd /tmp/microservices-build && \
    cmake /microservices && \
    make && \
    make install

# Update RIT helpers
cp /helpers/* /var/lib/irods/msiExecCmd_bin/.

# Mount ingest zones
# Note: 'mkdir -p' is idempotent and will not error if folder already exists
mkdir -p /mnt/ingest/zones && chmod 777 /mnt/ingest/zones

if [ "${USE_SAMBA}" = "true" ] ; then
    if [ -z "${INGEST_MOUNT}" ] || [ -z "${INGEST_USER}" ] || [ -z "${INGEST_PASSWORD}" ] || [ -z "${LDAP_PASSWORD}" ]; then     # -z is true when var is unset or equals empty string
         echo "ERROR: Make sure to specify INGEST_MOUNT, INGEST_USER, INGEST_PASSWORD and LDAP_PASSWORD values in secrets file when USE_SAMBA is true"
         exit 1
    else
         # mount CIFS on top of the created /mnt/ingest/zones folder
         mount -t cifs ${INGEST_MOUNT} /mnt/ingest/zones -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=999,gid=999,vers=1.0
    fi
else 
    echo "Using docker volume bind for dropzones instead of CIFS mount"
fi

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
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-tapeArchive

    # Add python rule engine to iRODS
    /opt/irods/add_rule_engine.py /etc/irods/server_config.json python 1

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}
    
    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resource vaults (i.e. dummy-mounts in development)
    mkdir -p /mnt/UM-hnas-4k
    chown irods:irods /mnt/UM-hnas-4k
    mkdir -p /mnt/UM-hnas-4k-repl
    chown irods:irods /mnt/UM-hnas-4k-repl
    # SURFsara Archive vault
    mkdir -p /mnt/SURF-Archive
    chown irods:irods /mnt/SURF-Archive

    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed

else
    service irods start
fi

# Force start of Metalnx RMD
service rmd restart

# logstash
/etc/init.d/filebeat start

# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*
