#!/usr/bin/env bash

debug_on_pattern='^(true|yes|1)$'
PS4='$0:$LINENO: '
if [[ "${DEBUG_DH_BOOTSTRAP,,}" =~ $debug_on_pattern ]]; then
    set -x
fi

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc AZM-storage unixfilesystem ${HOSTNAME}:/mnt/AZM-storage
iadmin mkresc AZM-storage-repl unixfilesystem ${HOSTNAME}:/mnt/AZM-storage-repl
iadmin mkresc replRescAZM01 replication
iadmin addchildtoresc replRescAZM01 AZM-storage
iadmin addchildtoresc replRescAZM01 AZM-storage-repl

# Add comment to resource for better identification in MDR's createProject dropdown
iadmin modresc ${HOSTNAME%%.dh.local}Resource comment AZM-CENTOS-INGEST-RESOURCE
iadmin modresc replRescAZM01 comment Replicated-resource-for-AZM

# Add storage pricing to resources
imeta add -R ${HOSTNAME%%.dh.local}Resource NCIT:C88193 999
imeta add -R replRescAZM01 NCIT:C88193 0

###########
## Projects and project permissions

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -r irods_rule_engine_plugin-python-instance -F /rules/tests/test_create_new_project.r  "*ingestResource='${HOSTNAME%%.dh.local}Resource'" "*resource='replRescAZM01'" "*title='(azM) ${PROJECTNAME}'" "*principalInvestigator='mcoonen'" "*dataSteward='opalmen'" "*responsibleCostCenter='AZM-123456'" "*extraParameters='{\"authorizationPeriodEndDate\":\"1-1-2018\", \"dataRetentionPeriodEndDate\":\"1-1-2018\", \"storageQuotaGb\":\"10\", \"enableOpenAccessExport\":\"false\", \"enableArchive\":\"true\", \"enableUnarchive\":\"true\",  \"enableDropzoneSharing\":\"true\", \"collectionMetadataSchemas\":\"DataHub_general_schema\"}'" | jq -r '.project_id')

    # Manage access
    ichmod -r own "mcoonen" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write datahub /nlmumc/projects/${project}

    # Viewer access
done

##########
## Special

