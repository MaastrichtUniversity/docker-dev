#!/bin/bash

set -e

until psql -h irods-db -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

# Update RIT rules
cd /rules && make

# Build RIT microservices
mkdir -p /tmp/microservices-build && \
    cd /tmp/microservices-build && \
    cmake /microservices && \
    make && \
    make install

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "23s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up the iCAT database
    /opt/irods/setupdb.sh /etc/irods/setup_responses

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-tapeArchive

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    su irods -c "/opt/irods/bootstrap_irods.sh"

    # Change default resource to rootResc for irods-user
    sed -i 's/\"irods_default_resource\"\:\ \"demoResc\"\,/\"irods_default_resource\"\:\ \"rootResc\"\,/' /var/lib/irods/.irods/irods_environment.json

    touch /var/run/irods_installed

else
    service irods start
fi

# Force start of Metalnx RMD
service rmd restart

#logstash
/etc/init.d/filebeat start

# this script must end with a persistent foreground process 
tail -F /var/lib/irods/log/rodsLog.* /var/lib/irods/log/reLog.*
