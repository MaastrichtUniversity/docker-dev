#!/bin/bash

until psql -h irods-db -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

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
else
    service irods start
fi

# this script must end with a persistent foreground process
tail -f /var/lib/irods/iRODS/server/log/rodsLog.*

