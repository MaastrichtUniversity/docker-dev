#!/bin/bash
#
# "Warning: scripts in /docker-entrypoint-initdb.d are only run if you start the container with a data directory that is empty"
# -- https://github.com/docker-library/docs/blob/master/postgres/README.md#initialization-scripts
#
# Creates iRODS user and iCAT database:
# Input:
#   - ${ENV_IRODS_DB_USERNAME}
#   - ${ENV_IRODS_DB_IRODS_PASSWORD}
#   - ${ENV_IRODS_DB_NAME}


psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d postgres <<-EOSQL
CREATE USER ${ENV_IRODS_DB_USERNAME} WITH PASSWORD '${ENV_IRODS_DB_IRODS_PASSWORD}';
CREATE DATABASE ${ENV_IRODS_DB_NAME};
GRANT ALL PRIVILEGES ON DATABASE ${ENV_IRODS_DB_NAME} TO ${ENV_IRODS_DB_USERNAME};
EOSQL
