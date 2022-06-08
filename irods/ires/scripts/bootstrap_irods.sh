#!/usr/bin/env bash

debug_on_pattern='^(true|yes|1)$'
PS4='$0:$LINENO: '
if [[ "${DEBUG_DH_BOOTSTRAP,,}" =~ $debug_on_pattern ]]; then
    set -x
fi

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc UM-hnas-4k unixfilesystem ${HOSTNAME}:/mnt/UM-hnas-4k
iadmin mkresc UM-hnas-4k-repl unixfilesystem ${HOSTNAME}:/mnt/UM-hnas-4k-repl
iadmin mkresc replRescUM01 replication
iadmin addchildtoresc replRescUM01 UM-hnas-4k
iadmin addchildtoresc replRescUM01 UM-hnas-4k-repl

# Create direct ingest resource and add DH-ingest access
imkdir -p /nlmumc/ingest/direct
iadmin mkresc stagingResc01 unixfilesystem ${HOSTNAME}:/mnt/stagingResc01
ichmod write DH-ingest /nlmumc/ingest/direct

# Add comment to resource for better identification in MDR's createProject dropdown
iadmin modresc ${HOSTNAME%%.dh.local}Resource comment UM-UBUNTU-INGEST-RESOURCE
iadmin modresc replRescUM01 comment Replicated-resource-for-UM

# Add storage pricing to resources
imeta add -R ${HOSTNAME%%.dh.local}Resource NCIT:C88193 999
imeta add -R replRescUM01 NCIT:C88193 0.130

###########
## Projects and project permissions

# FIXME: We expect icat to have created hardcoded projects P000000010 and
#        P000000011 at this point, but we can't be sure. So, just in case. We make
#        sure that test_create_new_project.r (-> create_new_project.py) thinks that
#        the latest project created is project 11.
#        Keeping in mind this is *not nice* and error prone.
#        Containers interdependencies is still a problem to solve for us.
imeta add -C /nlmumc/projects latest_project_number 11

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -r irods_rule_engine_plugin-python-instance -F /rules/tests/test_create_new_project.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME%%.dh.local}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='pvanschay2'" "*dataSteward='pvanschay2'" "*respCostCenter='UM-30001234X'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'" "*collectionMetadataSchemas='DataHub_general_schema,DataHub_extended_schema'" | jq -r '.project_id')

    # Manage access
    ichmod -r own "pvanschay2" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "pvanschay2" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write m4i-nanoscopy /nlmumc/projects/${project}

    # Viewer access
done

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -r irods_rule_engine_plugin-python-instance -F /rules/tests/test_create_new_project.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME%%.dh.local}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='psuppers'" "*dataSteward='opalmen'" "*respCostCenter='UM-30009998X'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'" "*collectionMetadataSchemas='DataHub_general_schema,DataHub_extended_schema'" | jq -r '.project_id')

    # Manage access
    ichmod -r own "psuppers" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write datahub /nlmumc/projects/${project}

    # Enable archiving for this project
    imeta set -C /nlmumc/projects/${project} enableArchive true
    # Enable export to Open Access for this project
    imeta set -C /nlmumc/projects/${project} enableOpenAccessExport true
    # Set the destination archive resource
    imeta set -C /nlmumc/projects/${project} archiveDestinationResource arcRescSURF01

    # Viewer access
done

for i in {01..1}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -r irods_rule_engine_plugin-python-instance -F /rules/tests/test_create_new_project.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME%%.dh.local}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='(ScaNxs) ${PROJECTNAME}'" "*principalInvestigator='mcoonen'" "*dataSteward='opalmen'" "*respCostCenter='UM-30009999X'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'" "*collectionMetadataSchemas='DataHub_general_schema'"  | jq -r '.project_id')

    # Manage access
    ichmod -r own "mcoonen" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write scannexus /nlmumc/projects/${project}

    # Viewer access
    ichmod -r read datahub /nlmumc/projects/${project}
done

##########
## Special
