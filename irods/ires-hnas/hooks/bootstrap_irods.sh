#!/usr/bin/env bash
# bootstrap_irods.sh creates the basic configuration for this resource and a
# mock environment (mock collections, projects, users, etc).
#
# Ideally, this should be split up into basic resource configuration (which we
# would need to actually re-recreate production config), and purely dev mockup
# environment tasks (creating fake collections, users, etc..).

# "Exit immediately if a command exits with a non-zero status." -- bash help set
set -e

# "Treat unset variables as an error when substituting."
set -u

# Set ENV_DEBUG_DH_BOOTSTRAP=yes for debug log lines
debug_on_pattern='^(true|yes|1)$'
PS4='$0:$LINENO: '
if [[ "${ENV_DEBUG_DH_BOOTSTRAP,,}" =~ $debug_on_pattern ]]; then
    # "Print commands and their arguments as they are executed."
    set -x
fi

source /opt/irods/lib/helpers.sh


create_mock_projects_azm() {
    for i in {01..2}; do
        project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,${ENV_IRODS_COOR_RESC_NAME},(azM) Test project #${i},dlinssen,opalmen,AZM-123456,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')

        imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
        imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
        imeta set -C ${project} storageQuotaGb '10'
        imeta set -C ${project} enableOpenAccessExport 'false'
        imeta set -C ${project} enableArchive 'true'
        imeta set -C ${project} enableUnarchive 'true'
        imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema'

        # Manage access
        ichmod -r own "dlinssen" ${project}

        # Data Steward gets manager rights
        ichmod -r own "opalmen" ${project}

        # Contributor access
        ichmod -r write datahub ${project}

        # Viewer access
    done
}

create_mock_projects_um() {
    for i in {01..2}; do
        project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,${ENV_IRODS_COOR_RESC_NAME},(UM) Test project #${i},psuppers,opalmen,UM-01234567890X,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')

        imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
        imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
        imeta set -C ${project} storageQuotaGb '10'
        imeta set -C ${project} enableOpenAccessExport 'false'
        imeta set -C ${project} enableArchive 'true'
        imeta set -C ${project} enableUnarchive 'true'
        imeta set -C ${project} enableDropzoneSharing 'true'
        if [ $? -eq 0 ]
        then
            imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema,DataHub_extended_schema'
        else
            imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema'
        fi

        # Manage access
        ichmod -r own "psuppers" ${project}

        # Data Steward gets manager rights
        ichmod -r own "opalmen" ${project}

        # Contributor access
        ichmod -r write datahub ${project}

        # Enable archiving for this project
        imeta set -C ${project} enableArchive true
        # Enable export to Open Access for this project
        imeta set -C ${project} enableOpenAccessExport true
        # Set the destination archive resource
        imeta set -C ${project} archiveDestinationResource arcRescSURF01

        # Viewer access
    done

    for i in {01..2}; do
        project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,${ENV_IRODS_COOR_RESC_NAME},(M4I) Test project #${i},pvanschay2,pvanschay2,UM-12345678901B,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')

        imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
        imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
        imeta set -C ${project} storageQuotaGb '10'
        imeta set -C ${project} enableOpenAccessExport 'false'
        imeta set -C ${project} enableArchive 'true'
        imeta set -C ${project} enableUnarchive 'true'
        imeta set -C ${project} enableDropzoneSharing 'true'
        if [ ${i} -eq 1 ]
        then
            imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema,DataHub_extended_schema'
        else
            imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema'
        fi

        # Manage access
        ichmod -r own "pvanschay2" ${project}

        # Data Steward gets manager rights
        ichmod -r own "pvanschay2" ${project}

        # Contributor access
        ichmod -r write m4i-nanoscopy ${project}

        # Viewer access
    done

    for i in {01..1}; do
        project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"${HOSTNAME%%.dh.local}Resource,${ENV_IRODS_COOR_RESC_NAME},(ScanNexus) Test project #${i},dlinssen,opalmen,UM-01234567890X,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')

        imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
        imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
        imeta set -C ${project} storageQuotaGb '10'
        imeta set -C ${project} enableOpenAccessExport 'false'
        imeta set -C ${project} enableArchive 'true'
        imeta set -C ${project} enableUnarchive 'true'
        imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema'

        # Manage access
        ichmod -r own "dlinssen" ${project}

        # Data Steward gets manager rights
        ichmod -r own "opalmen" ${project}

        # Contributor access
        ichmod -r write scannexus ${project}

        # Viewer access
        ichmod -r read datahub ${project}
    done
}


# This bootstrap_irods.sh (mock dev env for this iRES) depends on the
# successful (and finished) creation of the iCAT mock dev env.
# We extrapolate successful creation of iCAT mock dev env from
# bootstrap_irods_dev_mockup AVU on rootResc. Not great!
#
# retry_and_wait expects a function that probes state and outputs result
# Hacky: User facing log messages are printed out via stderr so retry_and_wait
#        doesn't capture those.
icat_mock_dev_env_probe() {
    local dev_icat_mock_env_state="undetermined"
    # we do `|| true` as we don't want to exit (set -e) if it errors out
    dev_icat_mock_env_state=$(imeta ls -R rootResc bootstrap_irods_dev_mockup | grep -Po '(value: \K.*)' || true)
    if [[ "$dev_icat_mock_env_state" =~ "complete" ]]; then
        echo "INFO: iCAT dev mock env seems to have been created. Can proceed with creation of ires dev mock env" 1>&2
    elif [[ "$dev_icat_mock_env_state" =~ "creating" ]]; then
        echo "INFO: iCAT dev mock env seems to be in the process of being created, or never fully finished" 1>&2
    else
        echo "INFO: Creation of iCAT dev mock env seems to not have been started yet" 1>&2
    fi

    # Will be "parsed" by retry_and_wait
    echo "state: $dev_icat_mock_env_state"
}

retry_and_wait icat_mock_dev_env_probe "state: complete" || { echo "ERROR: Gave up on iCAT mock dev env. Exiting.." ; exit 1; }

# Find out if this is not the first time this bootstrap_irods.sh has run the same iCAT.
# FIXME: We extrapolate from this AVU that all other operations in this
#        bootstrap_irods.sh have also been run. Not great!
dev_mockup_state=$(imeta ls -R ${ENV_IRODS_COOR_RESC_NAME} bootstrap_irods_dev_mockup | grep -Po '(value: \K.*)' || true)
if [[ "$dev_mockup_state" =~ "complete" ]]; then
    echo "INFO: This bootstrap_irods.sh seems to have already been run against the iCAT instance."
    echo "INFO: If you think this is a mistake, consider stopping and rm'ing icat and its database container."
    echo "INFO: Exiting early from bootstrap_irods.sh"
    exit 0
elif [[ "$dev_mockup_state" =~ "creating" ]]; then
    echo "WARNING: It looks like last time this iRES's bootstrap_irods.sh run against this iCAT, it didn't fully finish."
    echo "WARNING: It's probably easiest if you stop & rm the icat and icat db container."
    exit 1
else
    echo "INFO: It seems to be the first time this bootstrap_irods.sh is run against iCAT. Will continue running"
fi


############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc "${ENV_IRODS_STOR_RESC_NAME}" unixfilesystem "${HOSTNAME}:/mnt/${ENV_IRODS_STOR_RESC_NAME}"
iadmin mkresc "${ENV_IRODS_STOR_RESC_NAME}-repl" unixfilesystem "${HOSTNAME}:/mnt/${ENV_IRODS_STOR_RESC_NAME}-repl"
iadmin mkresc "${ENV_IRODS_COOR_RESC_NAME}" replication
iadmin addchildtoresc "${ENV_IRODS_COOR_RESC_NAME}" "${ENV_IRODS_STOR_RESC_NAME}"
iadmin addchildtoresc "${ENV_IRODS_COOR_RESC_NAME}" "${ENV_IRODS_STOR_RESC_NAME}-repl"

# We use this AVU to tell if this isn't the first time we ran this script against iCAT.
imeta add -R "${ENV_IRODS_COOR_RESC_NAME}" bootstrap_irods_dev_mockup "creating"

# There can only be one direct ingest resource
# if there is ever a need of more, we need to make the RescName a variable here
if [[ "$ENV_DIRECT_INGEST_RESOURCE" == "true" ]]; then
    # Create direct ingest resource and add DH-ingest access
    imkdir -p /nlmumc/ingest/direct
    iadmin mkresc stagingResc01 unixfilesystem ${HOSTNAME}:/mnt/stagingResc01
    ichmod write DH-ingest /nlmumc/ingest/direct
    imeta add -R stagingResc01 directIngestResc true
fi

# Add comment to resource for better identification in MDR's createProject dropdown
iadmin modresc ${HOSTNAME%%.dh.local}Resource comment "${ENV_IRODS_HOST_RESC_COMMENT}"
iadmin modresc ${ENV_IRODS_COOR_RESC_NAME} comment "${ENV_IRODS_COOR_RESC_COMMENT}"

# Add storage pricing to resources
imeta add -R ${HOSTNAME%%.dh.local}Resource NCIT:C88193 999
imeta add -R ${ENV_IRODS_COOR_RESC_NAME} NCIT:C88193 ${ENV_IRODS_COOR_RESC_PRICING}

###########
## Projects and project permissions

# TODO: This is prone to error. Mock dev environment creating could definitely use a major proper refactor!
#       We should never do something like this in production.
if [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "UM" ]]; then
    echo "INFO: Creating mock projects for UM because coordinating resource name contains word \"UM\""
    create_mock_projects_um
elif [[ "$ENV_IRODS_COOR_RESC_NAME" =~ "AZM" ]]; then
    echo "INFO: Creating mock projects for AZM because coordinating resource name contains word \"AZM\""
    create_mock_projects_azm
else
    echo "INFO: Coordinating resource name does not start with either \"UM\" or \"AZM\". No mock projects will be created."
fi


##########
## Special

imeta set -R ${ENV_IRODS_COOR_RESC_NAME} bootstrap_irods_dev_mockup "complete"
