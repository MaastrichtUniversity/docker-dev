#!/usr/bin/env bash
# NOTE: copy of externals/dh-irods/icat/scripts/bootstrap.sh (MaastrichtUniversity/dh-irods)
# Synced into this repo so the k8s manifests are self-contained. The Jenkins
# deploy pipeline may refresh this file from the pinned dh-irods checkout.

# Note `set -euo pipefail` in lib_irods.sh
source /opt/irods/lib/irods.sh
source /opt/irods/lib/helpers.sh

_main() {
    # wait for database to be ready
    until PGPASSWORD="${ENV_IRODS_DB_POSTGRES_PASSWORD}" psql -h "${ENV_IRODS_DB_HOSTNAME}" -U postgres -c '\l'; do
        >&2 echo "INFO: Postgres is unavailable - sleeping"
        sleep 1
    done

    # From Ubuntu 22.04 onward: start rsyslogd
    rsyslogd

    # iCAT: Remove ODBC iRODS log spam in the /tmp file [DHDO-1472]
    # See iRODS issue https://docs.irods.org/4.3.3/system_overview/troubleshooting/#large-number-of-postgresql-odbc-log-files-being-created-in-tmp
    sed -i 's/CommLog=1/CommLog=0/g' /etc/odbcinst.ini

    # install iRODS iCAT with our DH settings (if not already installed) & start service
    install_and_start_irods "icat"

    # Replace TAGS entry in filebeat.yml and start filebeat if present.
    if [[ -f /etc/filebeat/filebeat.yml ]]; then
        sed -i "s/\"FILEBEAT_PRIMARY_TAG\", \"FILEBEAT_SECONDARY_TAG\"/\"$ENV_FILEBEAT_PRIMARY_TAG\"/g" /etc/filebeat/filebeat.yml
    else
        echo "WARNING: /etc/filebeat/filebeat.yml not found, skipping filebeat tag configuration"
    fi

    if command -v filebeat >/dev/null 2>&1; then
        filebeat -c /etc/filebeat/filebeat.yml --strict.perms=false >/var/log/filebeat.log 2>&1 &
        echo "INFO: Started filebeat using binary"
    else
        echo "WARNING: filebeat is not available in this container, skipping startup"
    fi
}

_main "$@"
