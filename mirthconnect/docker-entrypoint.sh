#! /bin/bash

set -e

# Wait for postgres container to become available
until psql -h irods-db.dh.local -U postgres -c '\l'; do
  >&2 echo "Postgres is unavailable - sleeping"
  sleep 1
done

# Create database in postgres container
psql -h irods-db.dh.local -U postgres -d postgres <<- EOSQL
    DROP DATABASE IF EXISTS mirthdb;
    DROP USER "mirthconnect";

    CREATE USER mirthconnect WITH PASSWORD 'foobar';
    CREATE DATABASE mirthdb;
    GRANT ALL PRIVILEGES ON DATABASE mirthdb TO mirthconnect;
EOSQL

# Templating of the configuration.properties file
 sed -i "s/RIT_ENV/$RIT_ENV/" /opt/mirth-connect/appdata/configuration.properties

# Start MirthConnect service
./mcservice start

# Check if MirthConnect is running
until nc -z localhost 80; do
  echo "MirthConnect not started, sleeping"
  sleep 2
done

# Create users and import channels into MirthConnect using CLI
./mccommand -s /opt/mirth-script_config.txt

# force start of cron
service cron start

# Modify crontab to export channels every 15 minutes and remove old backups once a day
crontab /opt/crontab.txt


#logstash
/etc/init.d/filebeat start


# End with a persistent foreground process
tail -f /opt/mirth-connect/logs/mirth.log
