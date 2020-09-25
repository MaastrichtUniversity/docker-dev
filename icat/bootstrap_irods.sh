#!/usr/bin/env bash

set -e

############
## Resources

# Place a rootResc (passthru) in front of the default resource as described here https://docs.irods.org/4.1.8/manual/best_practices/
# This ensures that you can replace demoResc in the future without respecifying every client's default resource.
# The default resource for the zone (= rootResc) is included in a rit-policy (acSetRescSchemeForCreate)
iadmin mkresc rootResc passthru
iadmin addchildtoresc rootResc demoResc

# Add comment to resource for better identification in pacman's createProject dropdown
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

########
## Users
users="pvanschay2 mcoonen mcoonen2 dtheuniss psuppers rravelli gtria pahles delnoy rbrecheis jmelius kheinen snijhuis opalmen"

# In the real SRAM on production eduPersonUniqueId is a hash before the @-sign. Like this.
# "eduPersonUniqueId": "808d9b25-46da-4d5f-83ff-0d192368692f@sram.surf.nl"
# For simplicity, here we reuse the username. But we can't rely on it to be readable!
domain="sram.surf.nl"

for user in $users; do
    iadmin mkuser "${user}" rodsuser
    iadmin moduser "${user}" password foobar
    imeta add -u  "${user}" eduPersonUniqueID "${user}@${domain}"
done

snUsers="rvoncken"

for snUser in $snUsers; do
    iadmin mkuser "${snUser}" rodsuser
    iadmin moduser "${snUser}" password foobar
    imeta add -u  "${snUser}" eduPersonUniqueID "${snUser}@${domain}"
done

serviceUsers="service-dropzones service-mdl service-pid service-disqover"

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
nanoscopy="pvanschay2 gtria rravelli"

iadmin mkgroup SRAM-M4I-Nanoscopy
for user in $nanoscopy; do
    iadmin atg SRAM-M4I-Nanoscopy "${user}"
done

rit="pvanschay2 mcoonen mcoonen2 dtheuniss psuppers delnoy rbrecheis jmelius kheinen snijhuis"

iadmin mkgroup SRAM-DataHub
iadmin mkgroup DH-project-admins
for user in $rit; do
    iadmin atg SRAM-DataHub "${user}"
    iadmin atg DH-project-admins "${user}"
done

# Add all users created so far to the DH-ingest group
iadmin mkgroup DH-ingest
for user in $users; do
    iadmin atg DH-ingest "${user}"
done


scannexus="rvoncken"

iadmin mkgroup SRAM-SCANNEXUS
for user in $scannexus; do
    iadmin atg SRAM-SCANNEXUS "${user}"
    iadmin atg DH-ingest "${user}"
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

# Create a hardcoded project no. 10 for MDL data
imkdir -p /nlmumc/projects/P000000010
imeta add -C /nlmumc/projects/P000000010 authorizationPeriodEndDate 1-1-2018
imeta add -C /nlmumc/projects/P000000010 dataRetentionPeriodEndDate 1-1-2018
imeta add -C /nlmumc/projects/P000000010 ingestResource ${HOSTNAME}Resource
imeta add -C /nlmumc/projects/P000000010 OBI:0000103 psuppers
imeta add -C /nlmumc/projects/P000000010 dataSteward opalmen
imeta add -C /nlmumc/projects/P000000010 resource replRescAZM01
imeta add -C /nlmumc/projects/P000000010 responsibleCostCenter AZM-123456
imeta add -C /nlmumc/projects/P000000010 storageQuotaGb 10
imeta add -C /nlmumc/projects/P000000010 title "(MDL) Placeholder project"
irule -F /rules/projectCollection/createProjectCollection.r "*project='P000000010'" "*title='(MDL) Placeholder collection'"
ichmod -r own "psuppers" /nlmumc/projects/P000000010
# Data Steward gets manager rights
ichmod -r own "opalmen" /nlmumc/projects/P000000010
ichmod -r write "service-mdl" /nlmumc/projects/P000000010
ichmod -r read "SRAM-DataHub" /nlmumc/projects/P000000010
# Add additional AVUs
imeta add -C /nlmumc/projects/P000000010/C000000001 creator irods_bootstrap@docker.dev
imeta add -C /nlmumc/projects/P000000010/C000000001 dcat:byteSize 0
imeta add -C /nlmumc/projects/P000000010/C000000001 numFiles 0

# Create a hardcoded project no. 11 for HVC data
imkdir -p /nlmumc/projects/P000000011
imeta add -C /nlmumc/projects/P000000011 authorizationPeriodEndDate 1-1-2018
imeta add -C /nlmumc/projects/P000000011 dataRetentionPeriodEndDate 1-1-2018
imeta add -C /nlmumc/projects/P000000011 ingestResource ${HOSTNAME}Resource
imeta add -C /nlmumc/projects/P000000011 OBI:0000103 psuppers
imeta add -C /nlmumc/projects/P000000011 dataSteward opalmen
imeta add -C /nlmumc/projects/P000000011 resource replRescAZM01
imeta add -C /nlmumc/projects/P000000011 responsibleCostCenter AZM-123456
imeta add -C /nlmumc/projects/P000000011 storageQuotaGb 10
imeta add -C /nlmumc/projects/P000000011 title "(HVC) Placeholder project"
irule -F /rules/projectCollection/createProjectCollection.r "*project='P000000011'" "*title='(HVC) Placeholder collection'"
ichmod -r own "psuppers" /nlmumc/projects/P000000011
# Data Steward gets manager rights
ichmod -r own "opalmen" /nlmumc/projects/P000000011
ichmod -r write "service-mdl" /nlmumc/projects/P000000011
ichmod -r read "SRAM-DataHub" /nlmumc/projects/P000000011
# Add additional AVUs
imeta add -C /nlmumc/projects/P000000011/C000000001 creator irods_bootstrap@docker.dev
imeta add -C /nlmumc/projects/P000000011/C000000001 dcat:byteSize 0
imeta add -C /nlmumc/projects/P000000011/C000000001 numFiles 0

# Add data-steward specialty to certain users
imeta add -u "pvanschay2" "specialty" "data-steward"
imeta add -u "opalmen" "specialty" "data-steward"

# Add AVU on groups that should not be synced from LDAP
nonSyncGroups="rodsadmin DH-ingest public DH-project-admins"
for group in $nonSyncGroups; do
    imeta add -u "${group}" ldapSync false
done
