#!/bin/bash
sleep 10
set -e

source /etc/secrets

# Python requirements
# Need to upgrade pip from 8.1.2 to 20.3.4
# But pip2 cannot be upgrade to a version above 21 because of EOL
pip install --upgrade "pip < 21.0"
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
    patch --dry-run -f /var/lib/irods/scripts/setup_irods.py /opt/irods/add_ssl_setting_at_setup.patch
    if [[ $? -ne 0 ]]; then
        echo "Patching scripts/setup_irods.py is not possible with our patch"
    else
        patch -f /var/lib/irods/scripts/setup_irods.py /opt/irods/add_ssl_setting_at_setup.patch
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
    # NOTE: These lines are added to the server_config.json, but only go into effect when restarting the irods service!
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_URL ${EPICPID_URL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_USER ${EPICPID_USER}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_PASSWORD ${EPICPID_PASSWORD}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MDR_HANDLE_URL ${MDR_HANDLE_URL}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resource vaults (i.e. dummy-mounts in development)
    mkdir -p /mnt/UM-hnas-4k
    chown irods:irods /mnt/UM-hnas-4k
    mkdir -p /mnt/UM-hnas-4k-repl
    chown irods:irods /mnt/UM-hnas-4k-repl

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
