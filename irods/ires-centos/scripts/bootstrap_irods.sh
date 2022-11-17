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
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g'| sed 's/,/;/g')
    project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,replRescAZM01,(azM) ${PROJECTNAME},mcoonen,opalmen,AZM-123456,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')

    imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
    imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
    imeta set -C ${project} storageQuotaGb '10'
    imeta set -C ${project} enableOpenAccessExport 'false'
    imeta set -C ${project} enableArchive 'true'
    imeta set -C ${project} enableUnarchive 'true'
    imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema'

    # Manage access
    ichmod -r own "mcoonen" ${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" ${project}

    # Contributor access
    ichmod -r write datahub ${project}

    # Viewer access
done

##########
## Special

