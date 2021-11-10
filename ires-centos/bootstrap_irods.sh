#!/usr/bin/env bash

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc AZM-storage unixfilesystem ${HOSTNAME}:/mnt/AZM-storage
iadmin mkresc AZM-storage-repl unixfilesystem ${HOSTNAME}:/mnt/AZM-storage-repl
iadmin mkresc replRescAZM01 replication
iadmin addchildtoresc replRescAZM01 AZM-storage
iadmin addchildtoresc replRescAZM01 AZM-storage-repl

# Add comment to resource for better identification in MDR's createProject dropdown
iadmin modresc ${HOSTNAME}Resource comment AZM-CENTOS-INGEST-RESOURCE
iadmin modresc replRescAZM01 comment Replicated-resource-for-AZM

# Add storage pricing to resources
imeta add -R ${HOSTNAME}Resource NCIT:C88193 999
imeta add -R replRescAZM01 NCIT:C88193 0

###########
## Projects and project permissions

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescAZM01'" "*storageQuotaGb='10'" "*title='(azM) ${PROJECTNAME}'" "*principalInvestigator='mcoonen'" "*dataSteward='opalmen'" "*respCostCenter='AZM-123456'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'" "*collectionMetadataSchemas='DataHub_general_schema'")

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

