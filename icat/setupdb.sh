#!/bin/bash

# setupdb.sh
# Sets up a Postgres database for iRODS by creating a database and user and granting
# privileges to the user.

RESPFILE=$1
DBUSER=`tail -n 3 $RESPFILE | head -n 1`
DBPASS=`tail -n 2 $RESPFILE | head -n 1`
DBNAME=`tail -n 4 $RESPFILE | head -n 1`

psql -h irods-db -U postgres -d postgres <<- EOSQL
DROP DATABASE $DBNAME;
DROP USER "$DBUSER";

CREATE USER $DBUSER WITH PASSWORD '$DBPASS';
CREATE DATABASE $DBNAME;
GRANT ALL PRIVILEGES ON DATABASE $DBNAME TO $DBUSER;
EOSQL
