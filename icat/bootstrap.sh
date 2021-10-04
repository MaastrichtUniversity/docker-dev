#!/bin/bash

set -e
set -x

until psql -h irods-db.dh.local -U postgres -c '\l'; do
    >&2 echo "Postgres is unavailable - sleeping"
    sleep 1
done

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

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "23s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up the iCAT database
    /opt/irods/setupdb.sh /etc/irods/setup_responses

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

    # We already do this in ruleset / misc / policies
    #sed -i 's/CS_NEG_DONT_CARE/CS_NEG_REQUIRE/g' /etc/irods/core.re

    # Add python rule engine to iRODS
    /opt/irods/add_rule_engine.py /etc/irods/server_config.json python 1

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    # SURFsara Archive vault
    mkdir -p /mnt/SURF-Archive
    chown irods:irods /mnt/SURF-Archive

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
