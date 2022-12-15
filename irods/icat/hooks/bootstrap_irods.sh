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

source /opt/irods/lib_helpers.sh

# safety guard (bootstrap.sh should've already decided to (not) run this script
if [[ "$(print_is_dev_env)" != "yes" ]]; then
    echo "Safeguard: we don't seem to be in a dev environment. Will not run bootstrap_irods.sh"
    exit 1
fi

# Find out if this is not the first time this bootstrap_irods.sh has run the same iCAT DB.
# FIXME: We extrapolate from this AVU that all other operations in this
#        bootstrap_irods.sh have also been run. Not great!
# :( this would be more robust in python via python-irodsclient
dev_mockup_state=$(imeta ls -R rootResc bootstrap_irods_dev_mockup | grep -Po '(value: \K.*)' || true)
if [[ "$dev_mockup_state" =~ "complete" ]]; then
    echo "INFO: This bootstrap_irods.sh seems to have already been run against the iCAT DB."
    echo "INFO: If you think this is a mistake, consider stopping and rm'ing icat and its database container."
    exit 0
elif [[ "$dev_mockup_state" =~ "creating" ]]; then
    echo "WARNING: It looks like last time bootstrap_irods.sh run against this iCAT DB, it didn't fully finish."
    echo "WARNING: It's probably easiest if you stop & rm the icat and icat db container."
    exit 1
else
    echo "INFO: It seems to be the first time this bootstrap_irods.sh is run against iCAT DB. Will continue running"
fi


############
## Resources

# Place a rootResc (passthru) in front of the default resource as described here https://docs.irods.org/4.1.8/manual/best_practices/
# This ensures that you can replace demoResc in the future without respecifying every client's default resource.
# The default resource for the zone (= rootResc) is included in a rit-policy (acSetRescSchemeForCreate)
iadmin mkresc rootResc passthru
iadmin addchildtoresc rootResc demoResc

# We use this AVU to tell if this isn't the first time we ran this script against iCAT DB.
# It could be that the DB this iCAT is using has already configured all of this
imeta add -R rootResc bootstrap_irods_dev_mockup "creating"

# Add comment to resource for better identification in MDR's createProject dropdown
iadmin modresc rootResc comment DO-NOT-USE
iadmin modresc demoResc comment DO-NOT-USE

# Create a resource for the the SURFsara Archive
# Note: done by the icat container as all the projects created by ires containers are depending on this resource being available
iadmin mkresc arcRescSURF01 unixfilesystem ${HOSTNAME}:/mnt/SURF-Archive
# Add the archive service account to the Archive resource
imeta add -R arcRescSURF01 service-account service-surfarchive
# Set arcRescSURF01 as the archive destination resource, this AVU is required the createProject.r workflow
imeta add -R arcRescSURF01 archiveDestResc true

# Add storage pricing to resources
imeta add -R rootResc NCIT:C88193 999
imeta add -R demoResc NCIT:C88193 999
imeta add -R arcRescSURF01 NCIT:C88193 0.02

##############
## Collections
imkdir -p /nlmumc/ingest/zones
imkdir -p /nlmumc/projects


#######
## DH-ingest

# Create the group DH-ingest before the users, so we can add the new created users to it in the same loop
iadmin mkgroup DH-ingest

########
## Users

# users.json comes from docker-dev/keycloak/users.json
# To add new users or update an user, edit users.json
usersJSON=$(cat /opt/irods/users.json | jq -c '.')

echo $usersJSON | jq  -r -c '.[]'  | while read userJSON; do
    uid=$(echo $userJSON | jq -r -c '.userName' )
    # In the real SRAM on production eduPersonUniqueId is a hash before the @-sign. Like this.
    # "eduPersonUniqueId": "808d9b25-46da-4d5f-83ff-0d192368692f@sram.surf.nl"
    # For simplicity, here we reuse the username. But we can't rely on it to be readable!
    eduPersonUniqueId=$(echo $userJSON | jq -r -c '.eduPersonUniqueId' )
    voPersonExternalID=$(echo $userJSON | jq -r -c '.voPersonExternalID' )

    iadmin mkuser "${uid}" rodsuser
    iadmin moduser "${uid}" password foobar

    # eduPersonUniqueID is required for SRAM-sync to update the existing users
    imeta add -u  "${uid}" eduPersonUniqueID "${eduPersonUniqueId}"
    # voPersonExternalID is required for the drop-zone creation
    imeta add -u  "${uid}" voPersonExternalID "${voPersonExternalID}"

    # Add all users created so far to the DH-ingest group
    iadmin atg DH-ingest "${uid}"
done

serviceUsers="service-mdl service-pid service-disqover service-public"

for user in $serviceUsers; do
    iadmin mkuser "${user}" rodsuser
    iadmin moduser "${user}" password foobar
    imeta add -u "${user}" ldapSync false
done

serviceAdmins="service-surfarchive"

for user in $serviceAdmins; do
    iadmin mkuser "${user}" rodsadmin
    iadmin moduser "${user}" password foobar
    imeta add -u "${user}" ldapSync false
done

#########
## Groups
nanoscopy="pvanschay2"

iadmin mkgroup m4i-nanoscopy
for user in $nanoscopy; do
    iadmin atg m4i-nanoscopy "${user}"
done

rit="pvanschay2 mcoonen mcoonen2 dtheuniss psuppers rbrecheis jmelius tlustberg dlinssen"

iadmin mkgroup datahub
iadmin mkgroup DH-project-admins
for user in $rit; do
    iadmin atg datahub "${user}"
    iadmin atg DH-project-admins "${user}"
done


scannexus="rvoncken"

iadmin mkgroup scannexus
for user in $scannexus; do
    iadmin atg scannexus "${user}"
done

##############
## Permissions

# Make sure that all users (=members of group public) can browse to directories for which they have rights
ichmod read public /nlmumc
ichmod read public /nlmumc/projects

# Give the DH-ingest group write-access to the ingest-zones parent-collection
# This is needed because users need sufficient permissions to delete dropzone-collections by the msiRmColl operation in 'ingestNestedDelay2.r'
# See RITDEV-219 and RITDEV-422
ichmod write DH-ingest /nlmumc/ingest/zones

# Give the DH-project-admins write access on the projects folder for project creation trough the webform
ichmod write DH-project-admins /nlmumc/projects

###########
## Projects and project permissions
# Note: creation of projects will be handled by the respective resource servers


##########
## Special

# Rule that creates projects (irods-ruleset) depends on the existence of this AVU
imeta add -C /nlmumc/projects latest_project_number 0

# Add data-steward specialty to certain users
imeta add -u "pvanschay2" "specialty" "data-steward"
imeta add -u "opalmen" "specialty" "data-steward"

# Add AVU on groups that should not be synced from LDAP
nonSyncGroups="rodsadmin DH-ingest public DH-project-admins"
for group in $nonSyncGroups; do
    imeta add -u "${group}" ldapSync false
done

# Add special pre-defined sql queries to manage user temporary passwords
iadmin asq "DELETE FROM r_user_password WHERE user_id = ? AND pass_expiry_ts = '$ENV_IRODS_TEMP_PASSWORD_LIFETIME';" delete_password
iadmin asq "SELECT COUNT(*) FROM r_user_password WHERE user_id = ? AND pass_expiry_ts = '$ENV_IRODS_TEMP_PASSWORD_LIFETIME';" count_password
iadmin asq "SELECT create_ts FROM r_user_password WHERE user_id = ? AND pass_expiry_ts = '$ENV_IRODS_TEMP_PASSWORD_LIFETIME';" get_create_ts_password

# We make a mark in the DB signifying that the iCAT mock dev environment has
# been set up. Meaning, that this bootstrap_irods.sh has run.
imeta set -R rootResc bootstrap_irods_dev_mockup "complete"
