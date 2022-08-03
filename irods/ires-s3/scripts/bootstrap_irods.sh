#!/usr/bin/env bash

debug_on_pattern='^(true|yes|1)$'
PS4='$0:$LINENO: '
if [[ "${DEBUG_DH_BOOTSTRAP,,}" =~ $debug_on_pattern ]]; then
    set -x
fi

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc ${ENV_S3_RESC_NAME} s3 ${HOSTNAME}:/dh-irods-bucket-dev "S3_DEFAULT_HOSTNAME=${ENV_S3_HOST};S3_AUTH_FILE=/var/lib/irods/minio.keypair;S3_REGIONNAME=irods-dev;S3_RETRY_COUNT=1;S3_WAIT_TIME_SEC=3;S3_PROTO=HTTP;ARCHIVE_NAMING_POLICY=consistent;HOST_MODE=cacheless_attached;S3_CACHE_DIR=/cache"

# Sleep for a varying amount (3 * last digit of hostname) of seconds to prevent simultaneous checking for existence of replResc
SIMPLE_HOSTNAME=${HOSTNAME%%.dh.local}
sleep `expr ${SIMPLE_HOSTNAME: -1} \* 3`

# Check if repl resource exists, if not, create it
if [ "$(iadmin lr replRescUMCeph01)" == "No rows found" ];
then
  iadmin mkresc replRescUMCeph01 replication;
  iadmin modresc replRescUMCeph01 comment Replicated-Ceph-resource-for-UM
  imeta add -R replRescUMCeph01 NCIT:C88193 0.062
else
  echo "Replication resource already exists";
fi

# Add child resource to repl resource
iadmin addchildtoresc replRescUMCeph01 ${ENV_S3_RESC_NAME}

# Add comment to resource for better identification in MDR's createProject dropdown
iadmin modresc ${HOSTNAME%%.dh.local}Resource comment DO-NOT-USE

# Add storage pricing to resources
imeta add -R ${HOSTNAME%%.dh.local}Resource NCIT:C88193 999

###########
## Projects and project permissions

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -r irods_rule_engine_plugin-python-instance -F /rules/tests/test_create_new_project.r  "*ingestResource='iresResource'" "*resource='replRescUMCeph01'" "*title='(s3) ${PROJECTNAME}'" "*principalInvestigator='psuppers'" "*dataSteward='pvanschay2'" "*responsibleCostCenter='UM-01234567890R'" "*extraParameters='{\"authorizationPeriodEndDate\":\"1-1-2018\", \"dataRetentionPeriodEndDate\":\"1-1-2018\", \"storageQuotaGb\":\"10\", \"enableOpenAccessExport\":\"false\", \"enableArchive\":\"true\", \"enableUnarchive\":\"true\",  \"enableDropzoneSharing\":\"true\", \"collectionMetadataSchemas\":\"DataHub_general_schema\"}'"| jq -r '.project_id')

    # Manage access
    ichmod -r own "psuppers" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "pvanschay2" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write datahub /nlmumc/projects/${project}

    # Viewer access
done

##########
## Special
