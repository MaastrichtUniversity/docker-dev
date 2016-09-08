#! /bin/bash

set -e

source /etc/secrets

# Wait for postgres container to become available
until psql -h irods-db -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

# Create database in postgres container
psql -h irods-db -U postgres -d postgres <<- EOSQL
    DROP DATABASE IF EXISTS mirthdb;
    DROP USER "mirthconnect";

    CREATE USER mirthconnect WITH PASSWORD 'foobar';
    CREATE DATABASE mirthdb;
    GRANT ALL PRIVILEGES ON DATABASE mirthdb TO mirthconnect;
EOSQL


# Add Bitbucket server to known hosts
ssh-keyscan -p ${BITBUCKET_SERVER_PORT} ${BITBUCKET_SERVER} > /root/.ssh/known_hosts

# Clone the channels into the docker container
mkdir /opt/bitbucket/ && git clone -b v3.4.1.8057 $BITBUCKET_MIRTH_CHANNEL_REPO /opt/bitbucket/channels

# Start MirthConnect service
./mcservice start

# Check if MirthConnect is running
until nc -z localhost 9090; do
  echo "MirthConnect not started, sleeping"
  sleep 2
done

# Create users and import channels into MirthConnect using CLI
./mccommand -s /opt/mirth-config-script.txt

# End with a persistent foreground process
tail -f /opt/mirth-connect/logs/mirth.log