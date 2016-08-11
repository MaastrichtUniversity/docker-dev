#! /bin/bash

set -e

# Wait for postgres container to become available
until psql -h irods-db -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

# Create database in postgres container
psql -h irods-db -U postgres -d postgres <<- EOSQL
    DROP DATABASE mirthdb;
    DROP USER "mirthconnect";

    CREATE USER mirthconnect WITH PASSWORD 'foobar';
    CREATE DATABASE mirthdb;
    GRANT ALL PRIVILEGES ON DATABASE mirthconnect TO mirthdb;
EOSQL


# Add Bitbucket server to known hosts
ssh-keyscan -p ${BITBUCKET_SERVER_PORT} ${BITBUCKET_SERVER} >> /root/.ssh/known_hosts

# Clone the conf files into the docker container
mkdir /opt/bitbucket && git clone $BITBUCKET_MIRTH_CHANNEL_REPO /opt/bitbucket/channels


# TODO: Import channels into MirthConnect using CLI




if [ "$1" = 'java' ]; then
    chown -R mirth /opt/mirth-connect/appdata

    exec gosu mirth "$@"
fi

exec "$@"