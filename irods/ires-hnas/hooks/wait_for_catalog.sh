#!/usr/bin/env bash
# Backend startup needs resource DNS names before iCAT can open a seeded catalog.
set -euo pipefail
trap 'exit 143' TERM

if [[ "${ENV_IRODS_WAIT_FOR_CATALOG:-false}" == true ]]; then
    echo "INFO: Waiting for rit.sh to release resource startup after iCAT is ready."
    deadline=$((SECONDS + 600))
    until [[ -f /var/run/irods_catalog_ready ]]; do
        if (( SECONDS >= deadline )); then
            echo "ERROR: Timed out waiting for iCAT readiness." >&2
            exit 1
        fi
        sleep 1
    done
fi

exec /opt/irods/init.sh
