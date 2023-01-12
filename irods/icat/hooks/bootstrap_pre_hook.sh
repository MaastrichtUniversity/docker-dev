#!/bin/bash

set -euo pipefail

source /opt/irods/lib/irods.sh

_main() {
    # TODO: FIXME? Installing postgresql-client here, but bootstrap.sh will do it again.
    #              Problem is that this hook needs psql, but it's only installed in bootstrap.sh.
    #              I could make the hooks trigger in bootstrap.sh, but that would lead to duplicated code.
    wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
        && echo 'deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main' | sudo tee /etc/apt/sources.list.d/pgdg.list \
        && apt-get update \
        && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        postgresql-client-"${ENV_POSTGRES_CLIENT_VERSION}"

    local db_status=$(print_icat_db_status)

    # patch setup_irods.py so it doesn't break if DB was already populated from previous install
    if [[ "$db_status" == "setup" ]]; then
        # if db seems to be populated/created already
        echo "INFO: Applying setup_irods_already_installed_dev.patch to setup_irods.py"
        echo "INFO: This patch will comment out db creation and test_put()"
        patch_setup_irods /opt/irods/patch/setup_irods_already_installed_dev.patch || { echo "ERROR: Could not patch, exiting.." ; exit 1; }
    elif [[ "$db_status" == "created" ]]; then
        echo "INFO: iCAT database (postgres) does not seem to be set up. No patching required"
    elif [[ "$db_status" == "empty" ]]; then
        echo "ERROR: No iCAT database exists! icat-db container should have created it as part of its init"
        exit 1
    else
        echo "ERROR: Sanity checkpoint failed. We couldn't determine state of DB!"
        exit 1
    fi
}

_main "$@"
