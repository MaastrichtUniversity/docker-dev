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

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json ruleset-rit

    # Dirty temp.password workaround (TODO: NEEDS TO BE FIXED PROPERLY)
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 1200\,/' /etc/irods/server_config.json

    # iRODS settings
    ## Add resources
    ## TODO: Actual NFS mounts to HNAS storage need to be realized
    mkdir /mnt/hnasResc-UM-4k
    chown irods:irods /mnt/hnasResc-UM-4k
    mkdir /mnt/hnasResc-UM-32k
    chown irods:irods /mnt/hnasResc-UM-32k
    su - irods -c "iadmin mkresc hnasResc-UM-4k unixfilesystem ${HOSTNAME}:/mnt/hnasResc-UM-4k"
    su - irods -c "iadmin mkresc hnasResc-UM-32k unixfilesystem ${HOSTNAME}:/mnt/hnasResc-UM-32k"
    ## Create collections
    su - irods -c "imkdir /ritZone/ingestZone"
    su - irods -c "imkdir /ritZone/rawdata"
    su - irods -c "imkdir /ritZone/demo_mdl"
    su - irods -c "imkdir /ritZone/demo_ingest"
    su - irods -c "imkdir -p /ritZone/demo_ingest/Crohn"
    su - irods -c "imkdir -p /ritZone/demo_ingest/Melanoma"
    su - irods -c "imkdir -p /ritZone/demo_ingest/mol3dm"
    ## Specify ingest2resource as AVU for this collection
    su - irods -c "imeta add -C /ritZone/demo_ingest/Crohn resource hnasResc-UM-4k"
    su - irods -c "imeta add -C /ritZone/demo_ingest/Melanoma resource hnasResc-UM-32k"
    su - irods -c "imeta add -C /ritZone/demo_ingest/mol3dm resource hnasResc-UM-32k"


    # TODO: pam_ldap needs to be implemented
    su - irods -c "iadmin mkuser p.vanschayck rodsuser"
    su - irods -c "iadmin moduser p.vanschayck password foobar"
    su - irods -c "iadmin mkuser m.coonen rodsuser"
    su - irods -c "iadmin moduser m.coonen password foobar"
    su - irods -c "iadmin mkuser d.theunissen rodsuser"
    su - irods -c "iadmin moduser d.theunissen password foobar"
    su - irods -c "iadmin mkuser p.suppers rodsuser"
    su - irods -c "iadmin moduser p.suppers password foobar"

    # Make sure that all users (=members of group public) can browse to directories for which they have rights
    su - irods -c "ichmod read public /ritZone"

    # Make group
    su - irods -c "iadmin mkgroup ingest-zone"
    su - irods -c "iadmin atg ingest-zone p.vanschayck"
    su - irods -c "iadmin atg ingest-zone m.coonen"
    su - irods -c "iadmin atg ingest-zone d.theunissen"
    su - irods -c "iadmin atg ingest-zone p.suppers"

    # Set rights
    su - irods -c "ichmod -r own ingest-zone /ritZone/ingestZone"
    su - irods -c "ichmod -r write ingest-zone /ritZone/demo_mdl"
    su - irods -c "ichmod -r inherit /ritZone/demo_mdl"
    su - irods -c "ichmod -r write ingest-zone /ritZone/demo_ingest"
    su - irods -c "ichmod -r inherit /ritZone/demo_ingest"
    su - irods -c "ichmod -r own ingest-zone /ritZone/rawdata"

    # Mounted collection
    su - irods -c "imcoll -m filesystem /mnt/ingestZone/rawdata /ritZone/rawdata"
else
    service irods start
fi


# this script must end with a persistent foreground process
tail -f /var/lib/irods/iRODS/server/log/rodsLog.*
