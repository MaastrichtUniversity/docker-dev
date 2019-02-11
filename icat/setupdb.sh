#!/bin/bash

# setupdb.sh
# Sets up a Postgres database for iRODS by creating a database and user and granting
# privileges to the user.

RESPFILE=$1
DBNAME=`head -n 7 $RESPFILE | tail -n 1`
DBUSER=`head -n 8 $RESPFILE | tail -n 1`
DBPASS=`head -n 10 $RESPFILE | tail -n 1`

psql -h irods-db -U postgres -d postgres <<- EOSQL
DROP DATABASE $DBNAME;
DROP USER "$DBUSER";

CREATE USER $DBUSER WITH PASSWORD '$DBPASS';
CREATE DATABASE $DBNAME;
GRANT ALL PRIVILEGES ON DATABASE $DBNAME TO $DBUSER;
EOSQL
