#!/bin/bash

set -e

source /etc/secrets

until psql -h irods-db -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

# Update RIT rules
cd /rules && make install

# Update RIT microservices
cd /microservices && make install

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "14s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up the iCAT database
    /opt/irods/setupdb.sh /etc/irods/setup_responses

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
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_MDL_EXPORT_CHANNEL ${MIRTH_MDL_EXPORT_CHANNEL}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    su irods -c "/opt/irods/bootstrap_irods.sh"

    # Change default resource to rootResc for irods-user
    sed -i 's/\"irods_default_resource\"\:\ \"demoResc\"\,/\"irods_default_resource\"\:\ \"rootResc\"\,/' /var/lib/irods/.irods/irods_environment.json

    touch /var/run/irods_installed

    # Force restart of irods service (see iRODS 4.1.10 bug described in RITDEV-231)
    service irods restart
else
    service irods start
fi

# Force start of Metalnx RMD
service rmd restart

#logstash
/etc/init.d/filebeat start

# this script must end with a persistent foreground process 
tail -F /var/lib/irods/iRODS/server/log/rodsLog.* /var/lib/irods/iRODS/server/log/reLog.*
