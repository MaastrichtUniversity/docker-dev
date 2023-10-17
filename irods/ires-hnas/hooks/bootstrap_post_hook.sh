#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

# Update /etc/hosts file with help center url pointing to proxy ip address so it can be resolved in the container (only for dev)
echo "172.21.1.100 help.mdr.local.dh.unimaas.nl" >> /etc/hosts

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"

# Also create the S3 resources if we are in the UM container
if [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "UM" ]]; then
        echo "INFO: Now executing S3 bootstrap"
	su irods -c "/opt/irods/hooks/bootstrap_s3_ires.sh $ENV_S3_RESC_NAME_AC $ENV_S3_HOST_AC $ENV_S3_AUTH_FILE_AC $ENV_S3_RESC_NAME_GL $ENV_S3_HOST_GL $ENV_S3_AUTH_FILE_GL"
fi
