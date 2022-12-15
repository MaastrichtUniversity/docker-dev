#!/bin/bash

set -euo pipefail

source /opt/irods/lib_irods.sh

# Unreliably checks whether the iCAT database (postgres) is already populated
# by a previous setup_irods.py.
#
# Prints out as return:
#   'no': Database does not appear to be already set up. DB seem empty/clean.
#   'yes': Database seems to have already been setup and populated by an iCAT.
#   'undetermined': either the state of database could not be determined, or it's in a mixed state.
print_is_icat_db_setup() {
    # we will print this out (AND ONLY ECHO/PRINT THIS!)
    local is_db_setup="undetermined"

    # DB for icat exists?
    # See: https://stackoverflow.com/a/17757560
    local db_exists="undetermined"
    db_exists=$(PGPASSWORD=${ENV_IRODS_DB_POSTGRES_PASSWORD} psql -h "${ENV_IRODS_DB_HOSTNAME}" -U postgres -XAtc "SELECT 1 FROM pg_database WHERE datname = '${ENV_IRODS_DB_NAME}'")

    # User for irods exists?
    # See: https://stackoverflow.com/a/59833620
    local user_exists="undetermined"
    user_exists=$(PGPASSWORD=${ENV_IRODS_DB_POSTGRES_PASSWORD} psql -h "${ENV_IRODS_DB_HOSTNAME}" -U postgres -XAtc "SELECT 1 FROM pg_roles WHERE rolname = '${ENV_IRODS_DB_USERNAME}'")

    # Tables have been created inside icat DB? (setup_irods.py does this)
    local num_tables="undetermined"
    if [[ "$user_exists" == "1" ]]; then
        num_tables=$(PGPASSWORD=${ENV_IRODS_DB_IRODS_PASSWORD} psql -h "${ENV_IRODS_DB_HOSTNAME}" -U "${ENV_IRODS_DB_USERNAME}" -d "${ENV_IRODS_DB_NAME}" -XAtc "select count(*) from information_schema.tables where table_schema='public'")
    fi

    # Being overly explicit. FIXME: Logic...
    # If there are at least 21 tables, we naively take it as a sign of setup_irods.py having created iCAT tables
    if [[ "$db_exists" == "1" && "$user_exists" == "1" && "$num_tables" != "undetermined" && $num_tables -gt 20 ]]; then
        is_db_setup="yes"
    else
        is_db_setup="no"
    fi

    # Note: cmd_output_only_stdout=$(print_is_icat_db_setup)
    #       So, a cheap way of printing to the user/screen w/o messing with ""return""
    #echo "DEBUG: db_exists: \"$db_exists\"" 1>&2
    #echo "DEBUG: user_exists: \"$user_exists\"" 1>&2
    #echo "DEBUG: num_tables: \"$num_tables\"" 1>&2

    echo $is_db_setup
}

_main() {
    local was_db_setup=$(print_is_icat_db_setup)

    # patch setup_irods.py so it doesn't break if DB was already populated from previous install
    if [[ "$was_db_setup" == "yes" ]]; then
        # if db seems to be populated/created already
        echo "INFO: Applying setup_irods_already_installed_dev.patch to setup_irods.py"
        echo "INFO: This patch will comment out db creation and test_put()"
        patch_setup_irods /opt/irods/patch/setup_irods_already_installed_dev.patch || { echo "ERROR: Could not patch, exiting.." ; exit 1; }
    elif [[ "$was_db_setup" == "no" ]]; then
        echo "INFO: iCAT database (postgres) does not seem to be set up. No patching required"
    else
        echo "ERROR: Sanity checkpoint failed. We couldn't determine state of DB!"
        exit 1
    fi
}

_main "$@"
