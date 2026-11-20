#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

set -euo pipefail

# Catalog connectivity alone does not mean this resource server is ready yet.
deadline=$((SECONDS + 60))
until timeout 5s su irods -c 'ils /nlmumc/projects' >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
        echo "ERROR: Local iRODS server did not become ready for development bootstrap." >&2
        exit 1
    fi
    echo "INFO: Waiting for the local iRODS server before creating development fixtures."
    sleep 1
done

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"

# Also create the S3 resources if we are in the UM container
if [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "UM" ]]; then
        echo "INFO: Now executing S3 bootstrap"
	su irods -c "/opt/irods/hooks/bootstrap_s3_ires.sh $ENV_S3_RESC_NAME_AC $ENV_S3_HOST_AC $ENV_S3_AUTH_FILE_AC $ENV_S3_RESC_NAME_GL $ENV_S3_HOST_GL $ENV_S3_AUTH_FILE_GL"
fi
