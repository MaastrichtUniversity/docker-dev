#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"
#mkdir -p /var/lib/irods/log/
#echo "hello" > /var/lib/irods/log/reLog.test.txt
#chmod -R 777 /var/lib/irods/log/

if [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "UM" ]]; then
	echo "bootstrap_s3_ires $ENV_S3_RESC_NAME_AC  $ENV_S3_HOST_AC  $ENV_S3_AUTH_FILE_AC"
	su irods -c "/opt/irods/hooks/bootstrap_s3_ires.sh $ENV_S3_RESC_NAME_AC  $ENV_S3_HOST_AC  $ENV_S3_AUTH_FILE_AC"

	echo "bootstrap_s3_ires $ENV_S3_RESC_NAME_GL  $ENV_S3_HOST_GL  $ENV_S3_AUTH_FILE_GL"
	su irods -c "/opt/irods/hooks/bootstrap_s3_ires.sh $ENV_S3_RESC_NAME_GL  $ENV_S3_HOST_GL  $ENV_S3_AUTH_FILE_GL"
fi
