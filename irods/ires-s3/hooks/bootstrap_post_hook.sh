#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

echo "INFO: Now executing S3 bootstrap"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh $ENV_S3_RESC_NAME_AC $ENV_S3_HOST_AC $ENV_S3_AUTH_FILE_AC $ENV_S3_RESC_NAME_GL $ENV_S3_HOST_GL $ENV_S3_AUTH_FILE_GL"
