#!/usr/bin/env bash

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

# safety guard (bootstrap.sh should've already decided to (not) run this script
if [[ "$(print_is_dev_env)" != "yes" ]]; then
    echo "Safeguard: we don't seem to be in a dev environment. Will not run bootstrap_irods.sh"
    exit 1
fi


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
dev_mockup_state=$(imeta ls -R ${ENV_S3_RESC_NAME} bootstrap_irods_dev_mockup | grep -Po '(value: \K.*)' || true)
if [[ "$dev_mockup_state" =~ "complete" ]]; then
    # TODO: this should say INFO not WARNING? Change prototype test if you change this
    echo "WARNING: This bootstrap_irods.sh seems to have already been run against the iCAT instance."
    echo "INFO: If you think this is a mistake, consider stopping and rm'ing icat and its database container."
    exit 0
elif [[ "$dev_mockup_state" =~ "creating" ]]; then
    echo "WARNING: It looks like last time bootstrap_irods.sh run against this iCAT, it didn't fully finish."
    echo "WARNING: It's probably easiest if you stop & rm the icat and icat db container."
    exit 1
else
    echo "INFO: It seems to be the first time this bootstrap_irods.sh is run against iCAT. Will continue running"
fi


############
## Resources
iadmin mkresc ${ENV_S3_RESC_NAME} s3 ${HOSTNAME}:/dh-irods-bucket-dev "S3_DEFAULT_HOSTNAME=${ENV_S3_HOST};S3_AUTH_FILE=${S3_AUTH_FILE};S3_REGIONNAME=irods-dev;S3_RETRY_COUNT=1;S3_WAIT_TIME_SEC=3;S3_PROTO=HTTPS;ARCHIVE_NAMING_POLICY=consistent;HOST_MODE=cacheless_detached;S3_CACHE_DIR=/cache"

# We use this AVU to tell if this isn't the first time we ran this script against iCAT.
imeta add -R ${ENV_S3_RESC_NAME} bootstrap_irods_dev_mockup "creating"

# Sleep for a varying amount (3 * last digit of hostname) of seconds to prevent simultaneous checking for existence of replResc
# TODO: heh interesting way of minimizing chances of this race condition biting
#       us I guess :P, but of course doesn't solve it :p Is there an easier way to
#       solve it? Or at least minimize chances even further?
if grep -q "gl" <<< "${HOSTNAME%%.dh.local}"; then
  sleep 9
fi

# Check if repl ('coordinating') resource exists, if not, create it
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

echo "INFO: Creating mock projects"

for i in {01..2}; do
    project=$(irule -r irods_rule_engine_plugin-irods_rule_language-instance "test_rule_output(\"create_new_project\", \"ires-hnas-umResource,replRescUMCeph01,(S3-${ENV_S3_RESC_NAME: -2}) Test project #${i},psuppers,pvanschay2,UM-01234567890R,{'enableDropzoneSharing':'true'}\")" null ruleExecOut  |  jq -r '.project_path')

    imeta set -C ${project} authorizationPeriodEndDate '1-1-2018'
    imeta set -C ${project} dataRetentionPeriodEndDate '1-1-2018'
    imeta set -C ${project} storageQuotaGb '10'
    imeta set -C ${project} enableOpenAccessExport 'false'
    imeta set -C ${project} enableArchive 'true'
    imeta set -C ${project} enableUnarchive 'true'
    if [ ${i} -eq 1 ]
    then
        imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema,DataHub_extended_schema'
    else
        imeta set -C ${project} collectionMetadataSchemas 'DataHub_general_schema'
    fi

    # Manage access
    ichmod -r own "psuppers" ${project}

    # Data Steward gets manager rights
    ichmod -r own "pvanschay2" ${project}

    # Contributor access
    ichmod -r write datahub ${project}

    # Viewer access
done

##########
## Special

# TODO Update in 4.3.0
# While doing the iRODS unattended installation, default_general_json_configuration.json is pass to setup_irods.py
# But the value of 'default_resource_directory' is not picked up correctly
iadmin modresc ${HOSTNAME%%.dh.local}Resource path /var/lib/irods/vault

imeta set -R ${ENV_S3_RESC_NAME} bootstrap_irods_dev_mockup "complete"
