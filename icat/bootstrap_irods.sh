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

# Add storage pricing to resources
imeta add -R rootResc NCIT:C88193 999
imeta add -R demoResc NCIT:C88193 999

##############
## Collections
imkdir -p /nlmumc/ingest/zones
imkdir -p /nlmumc/projects

########
## Users
## for the most part users will by synced from LDAP, user defined here might be removed during synchronization!

snUsers="rick.voncken obsolete.user can.delete test.test"
snDomain="scannexus.nl"
for snUser in $snUsers; do
    iadmin mkuser "${snUser}@${snDomain}" rodsuser
    iadmin moduser "${snUser}@${snDomain}" password foobar
done

## technical users, not synced by sram-sync!
serviceUsers="service-dropzones service-mdl service-pid service-disqover"

for user in $serviceUsers; do
    iadmin mkuser "${user}" rodsuser
    iadmin moduser "${user}" password foobar
done
## technical users, not synced by sram-sync!
serviceAdmins="service-surfarchive"

for user in $serviceAdmins; do
    iadmin mkuser "${user}" rodsadmin
    iadmin moduser "${user}" password foobar
done

#########
## Groups
## currently the sram-sync script doesnt synchronize groups! However groups are created and filled with hardcoded users.
## For testing purposes we leave one externaly created (preexisting group here)

iadmin mkgroup nanoscopy-l

scannexus="rick.voncken"
iadmin mkgroup UM-SCANNEXUS
for user in $scannexus; do
    iadmin atg UM-SCANNEXUS "${user}@${snDomain}"
    iadmin atg DH-ingest "${user}@${snDomain}"
done

##############
## Sync LDAP Users
python3 ../sram-sync/sram-sync.py

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
imeta add -C /nlmumc/projects/P000000010 OBI:0000103 p.suppers@maastrichtuniversity.nl
imeta add -C /nlmumc/projects/P000000010 resource replRescAZM01
imeta add -C /nlmumc/projects/P000000010 responsibleCostCenter AZM-123456
imeta add -C /nlmumc/projects/P000000010 storageQuotaGb 10
imeta add -C /nlmumc/projects/P000000010 title "(MDL) Placeholder project"
irule -F /rules/projectCollection/createProjectCollection.r "*project='P000000010'" "*title='(MDL) Placeholder collection'"
ichmod -r own "p.suppers@maastrichtuniversity.nl" /nlmumc/projects/P000000010
ichmod -r write "service-mdl" /nlmumc/projects/P000000010
ichmod -r read "rit-l" /nlmumc/projects/P000000010
# Add additional AVUs
imeta add -C /nlmumc/projects/P000000010/C000000001 creator irods_bootstrap@docker.dev
imeta add -C /nlmumc/projects/P000000010/C000000001 dcat:byteSize 0
imeta add -C /nlmumc/projects/P000000010/C000000001 numFiles 0

# Create a hardcoded project no. 11 for HVC data
imkdir -p /nlmumc/projects/P000000011
imeta add -C /nlmumc/projects/P000000011 authorizationPeriodEndDate 1-1-2018
imeta add -C /nlmumc/projects/P000000011 dataRetentionPeriodEndDate 1-1-2018
imeta add -C /nlmumc/projects/P000000011 ingestResource ${HOSTNAME}Resource
imeta add -C /nlmumc/projects/P000000011 OBI:0000103 p.suppers@maastrichtuniversity.nl
imeta add -C /nlmumc/projects/P000000011 resource replRescAZM01
imeta add -C /nlmumc/projects/P000000011 responsibleCostCenter AZM-123456
imeta add -C /nlmumc/projects/P000000011 storageQuotaGb 10
imeta add -C /nlmumc/projects/P000000011 title "(HVC) Placeholder project"
irule -F /rules/projectCollection/createProjectCollection.r "*project='P000000011'" "*title='(HVC) Placeholder collection'"
ichmod -r own "p.suppers@maastrichtuniversity.nl" /nlmumc/projects/P000000011
ichmod -r write "service-mdl" /nlmumc/projects/P000000011
ichmod -r read "rit-l" /nlmumc/projects/P000000011
# Add additional AVUs
imeta add -C /nlmumc/projects/P000000011/C000000001 creator irods_bootstrap@docker.dev
imeta add -C /nlmumc/projects/P000000011/C000000001 dcat:byteSize 0
imeta add -C /nlmumc/projects/P000000011/C000000001 numFiles 0
