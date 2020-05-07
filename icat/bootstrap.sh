#!/bin/bash

set -e

until psql -h irods-db.dh.local -U postgres -c '\l'; do
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

# Generate SSL private key. certificate and Diffie-Hellman parameters
if [[ ! -e /opt/irods_ssl/server.key ]]; then
    openssl genrsa -out /opt/irods_ssl/server.key
    openssl req \
        -new -x509 -days 365 \
        -key /opt/irods_ssl/server.key\
        -out /opt/irods_ssl/server.crt \
        -subj "/C=NL/L=Maastricht/O=DataHub/CN=irods.dh.local"
    openssl dhparam -2 -out /opt/irods_ssl/dhparams.pem 2048
fi

# LDAP PAM
#ldap://ldap.dh.local
#ou=users,dc=datahubmaastricht,dc=nl
# ldap v3
# no local root admin
# login required
# Disable LDAP authentication for whole unix

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

    # Add SSL config to the server connection
    cat /var/lib/irods/.irods/irods_environment.json \
        | jq '. + {"irods_ssl_certificate_chain_file":"/opt/irods_ssl/server.crt"}' \
        | jq '. + {"irods_ssl_certificate_key_file":"/opt/irods_ssl/server.key"}' \
        | jq '. + {"irods_ssl_dh_params_file":"/opt/irods_ssl/dhparams.pem"}' \
        > /tmp/irods_environment.json
    mv /tmp/irods_environment.json /var/lib/irods/.irods/irods_environment.json

    #cat /var/lib/irods/.irods/irods_environment.json

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
