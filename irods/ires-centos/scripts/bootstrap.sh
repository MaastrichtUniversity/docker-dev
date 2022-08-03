#!/bin/bash

debug_on_pattern='^(true|yes|1)$'
PS4='$0:$LINENO: '
if [[ "${DEBUG_DH_BOOTSTRAP,,}" =~ $debug_on_pattern ]]; then
    set -x
fi

sleep 10
set -e

source /etc/secrets

# Python requirements
# Need to upgrade pip from 8.1.2 to 20.3.4
# But pip2 cannot be upgrade to a version above 21 because of EOL
pip install --upgrade "pip < 21.0"

# Update RIT rules
cd /rules && make

# Build RIT microservices
mkdir -p /tmp/microservices-build && \
    cd /tmp/microservices-build && \
    cmake3 /microservices && \
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
         mount -t cifs ${INGEST_MOUNT} /mnt/ingest/zones -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=999,gid=999,vers=2.0
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

    # PoC: patch setup_irods.py to accept SSL settings
    patch --dry-run -f /var/lib/irods/scripts/setup_irods.py /opt/irods/patch/add_ssl_setting_at_setup.patch
    if [[ $? -ne 0 ]]; then
        echo "Patching scripts/setup_irods.py is not possible with our patch"
    else
        patch -f /var/lib/irods/scripts/setup_irods.py /opt/irods/patch/add_ssl_setting_at_setup.patch
    fi

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-policies
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-tapeArchive

    # Add python rule engine to iRODS
    /opt/irods/add_rule_engine.py /etc/irods/server_config.json python 1

    # Add config variable to iRODS
    # NOTE: These lines are added to the server_config.json, but only go into effect when restarting the irods service!
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_TEMP_PASSWORD_LIFETIME ${IRODS_TEMP_PASSWORD_LIFETIME}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_URL ${EPICPID_URL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_USER ${EPICPID_USER}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_PASSWORD ${EPICPID_PASSWORD}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MDR_HANDLE_URL ${MDR_HANDLE_URL}
    
    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ '$IRODS_TEMP_PASSWORD_LIFETIME'\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resource vaults (i.e. dummy-mounts in development)
    mkdir /mnt/AZM-storage
    chown irods:irods /mnt/AZM-storage
    mkdir /mnt/AZM-storage-repl
    chown irods:irods /mnt/AZM-storage-repl

    # Install pip packages from python requirements for the irods user
    su irods -c "pip install --user -r /rules/python/python_requirements.txt"
    # Go into the iRODS specific bootstrap
    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed

else
    service irods start
fi

# Copy the service-control scripts outside of /etc/init.d folder to prevent D-Bus kicking in & force the service to start
# Logstash
cp /etc/init.d/filebeat /opt/filebeat && /opt/filebeat restart

# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*