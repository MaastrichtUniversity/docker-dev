#! /bin/bash

set -e

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

until psql -h mpi-tempdb -U postgres -c '\l'; do
  >&2 echo "Postgres MPI is unavailable - sleeping"
  sleep 1
done

psql -h mpi-tempdb -U postgres -d postgres <<- EOSQL
    CREATE USER mpi WITH PASSWORD 'foobar';
    CREATE DATABASE mpitempdb;
    GRANT ALL PRIVILEGES ON DATABASE mpitempdb TO mpi;
EOSQL
psql -h mpi-tempdb -U mpi -d mpitempdb <<- EOSQL
    CREATE TABLE mpilookup(
        id SERIAL,
        orgid CHAR(50),
        euid CHAR(50)
    );
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
./mccommand -s /opt/mirth-config-script.txt


#logstash
/etc/init.d/filebeat start


# End with a persistent foreground process
tail -f /opt/mirth-connect/logs/mirth.log