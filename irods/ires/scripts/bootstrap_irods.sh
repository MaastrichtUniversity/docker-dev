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
imeta add -R stagingResc01 directIngestResc true

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
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g'| sed 's/,/;/g')
    echo $PROJECTNAME
    project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,replRescUM01,${PROJECTNAME},pvanschay2,pvanschay2,UM-12345678901B,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')
    echo "m4i-nanoscopy"
    echo $project
    imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
    imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
    imeta set -C ${project} storageQuotaGb '10'
    imeta set -C ${project} enableOpenAccessExport 'false'
    imeta set -C ${project} enableArchive 'true'
    imeta set -C ${project} enableUnarchive 'true'
    imeta set -C ${project} enableDropzoneSharing 'true'
    imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema,DataHub_extended_schema'

    # Manage access
    ichmod -r own "pvanschay2" ${project}

    # Data Steward gets manager rights
    ichmod -r own "pvanschay2" ${project}

    # Contributor access
    ichmod -r write m4i-nanoscopy ${project}

    # Viewer access
done

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g'| sed 's/,/;/g')
    echo $PROJECTNAME
    project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,replRescUM01,${PROJECTNAME},psuppers,opalmen,UM-01234567890X,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')
    echo "datahub"
    echo $project
    imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
    imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
    imeta set -C ${project} storageQuotaGb '10'
    imeta set -C ${project} enableOpenAccessExport 'false'
    imeta set -C ${project} enableArchive 'true'
    imeta set -C ${project} enableUnarchive 'true'
    imeta set -C ${project} enableDropzoneSharing 'true'
    imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema,DataHub_extended_schema'

    # Manage access
    ichmod -r own "psuppers" ${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" ${project}

    # Contributor access
    ichmod -r write datahub ${project}

    # Viewer access
done

for i in {01..1}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g'| sed 's/,/;/g')
    echo $PROJECTNAME
    project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,replRescUM01,(ScaNxs) ${PROJECTNAME},psuppers,opalmen,UM-01234567890X,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')
    echo "scannexus"
    echo $project
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
    ichmod -r write scannexus ${project}

    # Viewer access
    ichmod -r read datahub ${project}
done

##########
## Special
