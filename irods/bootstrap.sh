#!/bin/bash

source /etc/secrets

until psql -h irods-db -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

# Update RIT helpers
cp /helpers/* /var/lib/irods/iRODS/server/bin/cmd/.

# Update RIT rules
cd /rules && make install

# Mount ingest zone
mount -t cifs ${INGEST_MOUNT} /mnt/ingestZone -o user=${INGEST_USER},password=${INGEST_PASSWORD},uid=999,gid=999

# Check if this is a first run of this container
if [[ ! -e /etc/irods/setup_responses ]]; then

    # generate configuration responses
    /opt/irods/genresp.sh /etc/irods/setup_responses

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "14s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up the iCAT database
    /opt/irods/setupdb.sh /etc/irods/setup_responses

    # set up iRODS
    /opt/irods/config.sh /etc/irods/setup_responses

    # change irods user's irodsEnv file to point to localhost, since it was configured with a transient Docker container's $
    sed -i 's/^irodsHost.*/irodsHost localhost/' /var/lib/irods/.irods/.irodsEnv

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json ruleset-rit

    # iRODS settings
    su - irods -c "imkdir /ritZone/ingestZone"
    su - irods -c "imkdir /ritZone/archive"

    # TODO: pam_ldap needs to be implemented
    su - irods -c "iadmin mkuser p.vanschayck rodsuser"
    su - irods -c "iadmin moduser p.vanschayck password foobar"
    su - irods -c "iadmin mkuser m.coonen rodsuser"
    su - irods -c "iadmin moduser m.coonen password foobar"
    su - irods -c "iadmin mkuser d.theunissen rodsuser"
    su - irods -c "iadmin moduser d.theunissen password foobar"
    su - irods -c "iadmin mkuser p.suppers rodsuser"
    su - irods -c "iadmin moduser p.suppers password foobar"

    # Make group
    su - irods -c "iadmin mkgroup ingest-zone"
    su - irods -c "iadmin atg ingest-zone p.vanschayck"
    su - irods -c "iadmin atg ingest-zone m.coonen"
    su - irods -c "iadmin atg ingest-zone d.theunissen"
    su - irods -c "iadmin atg ingest-zone p.suppers"

    # Set rights
    su - irods -c "ichmod own ingest-zone /ritZone/ingestZone"
    su - irods -c "ichmod own ingest-zone /ritZone/archive"
else
    service irods start
fi

# this script must end with a persistent foreground process
tail -f /var/lib/irods/iRODS/server/log/rodsLog.*