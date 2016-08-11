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


if [ "$1" = 'java' ]; then
    chown -R mirth /opt/mirth-connect/appdata

    exec gosu mirth "$@"
fi

exec "$@"