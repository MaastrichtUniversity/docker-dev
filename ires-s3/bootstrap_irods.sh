#!/usr/bin/env bash

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc ${ENV_S3_RESC_NAME} s3 ${HOSTNAME}:/dh-irods-bucket-dev "S3_DEFAULT_HOSTNAME=${ENV_S3_HOST};S3_AUTH_FILE=/var/lib/irods/minio.keypair;S3_REGIONNAME=irods-dev;S3_RETRY_COUNT=1;S3_WAIT_TIME_SEC=3;S3_PROTO=HTTP;ARCHIVE_NAMING_POLICY=consistent;HOST_MODE=cacheless_attached;S3_CACHE_DIR=/cache"

# Sleep for a varying amount (3 * last digit of hostname) of seconds to prevent simultaneous checking for existence of replResc
sleep `expr ${HOSTNAME: -1} \* 3`

# Check if repl resource exists, if not, create it
if [ "$(iadmin lr replRescUMCeph01)" == "No rows found" ];
then
  iadmin mkresc replRescUMCeph01 replication;
  iadmin modresc replRescUMCeph01 comment Replicated-resource-for-S3
  imeta add -R replRescUMCeph01 NCIT:C88193 0.062
else
  echo "Replication resource already exists";
fi

# Add child resource to repl resource
iadmin addchildtoresc replRescUMCeph01 ${ENV_S3_RESC_NAME}

# Add comment to resource for better identification in pacman's createProject dropdown
iadmin modresc ${HOSTNAME}Resource comment DO-NOT-USE

# Add storage pricing to resources
imeta add -R ${HOSTNAME}Resource NCIT:C88193 999

###########
## Projects and project permissions
domain="maastrichtuniversity.nl"

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='iresResource'" "*resource='replRescUMCeph01'" "*storageQuotaGb='10'" "*title='(s3) ${PROJECTNAME}'" "*principalInvestigator='p.suppers@${domain}'" "*dataSteward='p.vanschayck@${domain}'" "*respCostCenter='UM-30001234X'")

    # Manage access
    ichmod -r own "p.suppers@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write DataHub /nlmumc/projects/${project}

    # Viewer access
done

##########
## Special

