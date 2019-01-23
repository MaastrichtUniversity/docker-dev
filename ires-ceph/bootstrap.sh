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
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed

    # Force restart of irods service (see iRODS 4.1.10 bug described in RITDEV-231)
    service irods restart
else
    service irods start
fi

# Install irods librados plugin:
echo "compiling irods rados plugin"
cd /var/tmp && git clone https://github.com/irods/irods_resource_plugin_rados.git
cd /var/tmp/irods_resource_plugin_rados && git checkout 4-1-stable && make && make install

touch /etc/irods/irados.config && chown irods: /etc/irods/irados.config && chmod 600 /etc/irods/irados.config
echo "[global]
	mon host = ${CEPHGLMONHOST}
    
[${CEPHGLUSER}]
	key = ${CEPHGLKEY}" > /etc/irods/irados.config

# Force start of Metalnx RMD
service rmd restart

#logstash
/etc/init.d/filebeat start

# this script must end with a persistent foreground process
tail -F /var/lib/irods/iRODS/server/log/rodsLog.*
