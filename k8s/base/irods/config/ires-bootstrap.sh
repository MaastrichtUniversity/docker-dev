#!/usr/bin/env bash
# NOTE: copy of externals/dh-irods/ires-hnas/scripts/bootstrap.sh (MaastrichtUniversity/dh-irods)
# Synced into this repo so the k8s manifests are self-contained. The Jenkins
# deploy pipeline may refresh this file from the pinned dh-irods checkout.
#
# k8s note: the dockerize wait below (200s) is backstopped by a `wait-icat`
# init container in the StatefulSet that waits up to an hour for iCAT.

# Note `set -euo pipefail` in lib/irods.sh
source /opt/irods/lib/irods.sh
source /opt/irods/lib/helpers.sh


# TODO: Make Control-Cing work fast, and handle signals reliably
# (trap _trap_sigterm SIGTERM ..)

# A series of tests that will fail if we are missing variables, volume maps, etc..
flight_checks() {
    local expected_dirs+=(
        "/mnt/${ENV_IRODS_STOR_RESC_NAME}"
        "/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
        "/mnt/ingest/zones"
        "/var/log/irods-pre-ingest"
    )

    local missing_dirs="no"
    for expected_dir in "${expected_dirs[@]}"; do
        if [[ ! -d "$expected_dir" ]]; then
            # If the coordinating resource is a 'passthru' resource, there is only one child and therefore not crash on the 'repl' dir missing
            # this is a dirty workaround that should probably be fixed at some point in time.
            if [[ "${ENV_IRODS_COOR_RESC_NAME}" =~ "pass" && "$expected_dir" =~ "repl" ]]; then
                continue
            fi
            echo "ERROR: Could not find \"$expected_dir\""
            echo "ERROR: Does it exist? Perhaps you want to volume map it or fake it via pre_hook."
            missing_dirs="yes"
        else
            echo "INFO: Found expected directory \"$expected_dir\""
        fi
    done

    # TODO!! Check for owner:group and permissions here
    # We used to do:
    #   chown irods:irods /mnt/ingest/zones
    #   chown irods:irods /mnt/stagingResc01
    #   chown irods:irods /var/log/irods-pre-ingest
    # But we need to understand NFS, CIFS permissions better

    # TODO: This is a temporary workaround
    if [[ "${ENV_IRODS_STOR_RESC_NAME}" =~ "UM" ]]; then
        echo "INFO: ires-hnas contains \"UM\" in resource name. Assuming direct ingest is expected"
        if [[ ! -d "/mnt/stagingResc01" ]]; then
            echo "ERROR: Could not find \"/mnt/stagingResc01\""
            missing_dirs="yes"
        else
            echo "INFO: Found expected directory \"/mnt/stagingResc01\""
        fi
    else
        echo "INFO: ires-hnas does not contain \"UM\" in resource name. Assuming direct ingest is NOT expected."
    fi


    if [[ "$missing_dirs" == "yes" ]]; then
        exit 1
    fi
}

_main() {
    flight_checks

    # Wait for iCAT to become _seemingly_ ready
    dockerize -wait tcp://${ENV_IRODS_ICAT_HOST:=icat.dh.local}:1247 -timeout 200s

    # From Ubuntu 22.04 onward: start rsyslogd
    rsyslogd

    # install iRODS iCAT with our DH settings (if not already installed) & start service
    install_and_start_irods "ires"

    # The iRODS S3 plugin reads "<access_key> <secret_key>" from S3_AUTH_FILE
    # (see mkresc in hooks/bootstrap_s3_ires.sh). In the compose stack those
    # files were created manually once on the bind-mounted /var/lib/irods; on
    # a fresh k8s vault PVC they must be created here. Idempotent: only writes
    # when missing, and only when the S3 key env vars are present (UM side only).
    if [[ -n "${ENV_S3_ACCESS_KEY_AC:-}" ]]; then
        _write_s3_keypair() {
            local file=$1 access=$2 secret=$3
            if [[ ! -f "$file" && -n "$access" && -n "$secret" ]]; then
                (umask 077; printf '%s %s\n' "$access" "$secret" > "$file")
                chown irods:irods "$file"
                echo "INFO: Created S3 keypair file $file"
            fi
        }
        [[ -n "${ENV_S3_AUTH_FILE_AC:-}" ]] && _write_s3_keypair "$ENV_S3_AUTH_FILE_AC" "$ENV_S3_ACCESS_KEY_AC" "$ENV_S3_SECRET_KEY_AC"
        [[ -n "${ENV_S3_AUTH_FILE_GL:-}" ]] && _write_s3_keypair "$ENV_S3_AUTH_FILE_GL" "$ENV_S3_ACCESS_KEY_GL" "$ENV_S3_SECRET_KEY_GL"
    fi

    # Replace TAGS entry in filebeat.yml and start filebeat if present.
    if [[ -f /etc/filebeat/filebeat.yml ]]; then
        sed -i "s/\"FILEBEAT_PRIMARY_TAG\"/\"$ENV_FILEBEAT_PRIMARY_TAG\"/g" /etc/filebeat/filebeat.yml
        sed -i "s/\"FILEBEAT_SECONDARY_TAG\"/\"$ENV_FILEBEAT_SECONDARY_TAG\"/g" /etc/filebeat/filebeat.yml
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
