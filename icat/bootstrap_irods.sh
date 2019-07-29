#!/usr/bin/env bash

set -e

############
## Resources

# Place a rootResc (passthru) in front of the default resource as described here https://docs.irods.org/4.1.8/manual/best_practices/
# This ensures that you can replace demoResc in the future without respecifying every client's default resource.
# The default resource for the zone (= rootResc) is included in a rit-policy (acSetRescSchemeForCreate)
iadmin mkresc rootResc passthru
iadmin addchildtoresc rootResc demoResc




# Create resources and make them members of the (composable) replication resource.
iadmin mkresc replRescUM01 replication
iadmin mkresc UM-hnas-4k unixfilesystem ${IRODS_RESOURCE_HOST_DEB}:/mnt/UM-hnas-4k
iadmin mkresc UM-hnas-4k-repl unixfilesystem ${IRODS_RESOURCE_HOST_DEB}:/mnt/UM-hnas-4k-repl
iadmin addchildtoresc replRescUM01 UM-hnas-4k
iadmin addchildtoresc replRescUM01 UM-hnas-4k-repl

iadmin mkresc replRescAZM01 replication
iadmin mkresc AZM-storage unixfilesystem ${IRODS_RESOURCE_HOST_RPM}:/mnt/AZM-storage
iadmin mkresc AZM-storage-repl unixfilesystem ${IRODS_RESOURCE_HOST_RPM}:/mnt/AZM-storage-repl
iadmin addchildtoresc replRescAZM01 AZM-storage
iadmin addchildtoresc replRescAZM01 AZM-storage-repl

# Add comment to resource for better identification in dropdown
iadmin modresc rootResc comment DO-NOT-USE
iadmin modresc demoResc comment DO-NOT-USE
iadmin modresc replRescUM01 comment Replicated-resource-for-UM
iadmin modresc replRescAZM01 comment Replicated-resource-for-AZM

# Add storage pricing to resources
imeta add -R rootResc NCIT:C88193 999
imeta add -R demoResc NCIT:C88193 999
imeta add -R replRescUM01 NCIT:C88193 0.189
imeta add -R replRescAZM01 NCIT:C88193 0

##############
## Collections
imkdir -p /nlmumc/ingest/zones
imkdir -p /nlmumc/projects

########
## Users
users="p.vanschayck m.coonen d.theunissen p.suppers rbg.ravelli g.tria p.ahles delnoy r.niesten r.brecheisen jonathan.melius k.heinen s.nijhuis"
domain="maastrichtuniversity.nl"

for user in $users; do
    iadmin mkuser "${user}@${domain}" rodsuser
    iadmin moduser "${user}@${domain}" password foobar
done

snUsers="rick.voncken"
snDomain="scannexus.nl"

for snUser in $snUsers; do
    iadmin mkuser "${snUser}@${snDomain}" rodsuser
    iadmin moduser "${snUser}@${snDomain}" password foobar
done

serviceUsers="service-dropzones service-mdl service-dwh service-pid service-disqover"

for user in $serviceUsers; do
    iadmin mkuser "${user}" rodsuser
    iadmin moduser "${user}" password foobar
done

serviceAdmins="service-surfarchive"

for user in $serviceAdmins; do
    iadmin mkuser "${user}" rodsadmin
    iadmin moduser "${user}" password foobar
done

#########
## Groups
nanoscopy="p.vanschayck g.tria rbg.ravelli"

iadmin mkgroup nanoscopy-l
for user in $nanoscopy; do
    iadmin atg nanoscopy-l "${user}@${domain}"
done

rit="p.vanschayck m.coonen d.theunissen p.suppers delnoy r.niesten r.brecheisen jonathan.melius k.heinen s.nijhuis"

iadmin mkgroup rit-l
iadmin mkgroup DH-project-admins
for user in $rit; do
    iadmin atg rit-l "${user}@${domain}"
    iadmin atg DH-project-admins "${user}@${domain}"
done

# Add all users created so far to the DH-ingest group
iadmin mkgroup DH-ingest
for user in $users; do
    iadmin atg DH-ingest "${user}@${domain}"
done


scannexus="rick.voncken"

iadmin mkgroup UM-SCANNEXUS
for user in $scannexus; do
    iadmin atg UM-SCANNEXUS "${user}@${snDomain}"
    iadmin atg DH-ingest "${user}@${snDomain}"
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

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${IRODS_RESOURCE_HOST_DEB}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.vanschayck@${domain}'" "*respCostCenter='UM-30001234X'")

    # Contributor access for nanoscopy
    ichmod -r write nanoscopy-l /nlmumc/projects/${project}
    # Manage access for Paul
    ichmod -r own "p.vanschayck@${domain}" /nlmumc/projects/${project}
done

for i in {01..3}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${IRODS_RESOURCE_HOST_DEB}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.suppers@${domain}'" "*respCostCenter='UM-30009998X'")

    # Contributor access for RIT
    ichmod -r write rit-l /nlmumc/projects/${project}
    # Manage access for suppers
    ichmod -r own "p.suppers@${domain}" /nlmumc/projects/${project}
done

for i in {01..3}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${IRODS_RESOURCE_HOST_DEB}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='d.theunissen@${domain}'" "*respCostCenter='UM-30009999X'")

    # Read access for rit
    ichmod -r read rit-l /nlmumc/projects/${project}

    # Manage access for Daniel
    ichmod -r own "d.theunissen@${domain}" /nlmumc/projects/${project}

    # Contributor access for Maarten
    ichmod -r write "m.coonen@${domain}" /nlmumc/projects/${project}
done

for i in {01..4}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${IRODS_RESOURCE_HOST_DEB}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.suppers@${domain}'" "*respCostCenter='UM-30009999X'")

    # Contributor access for RIT
    ichmod -r write rit-l /nlmumc/projects/${project}
    # Manage access for suppers
    ichmod -r own "p.suppers@${domain}" /nlmumc/projects/${project}
done

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${IRODS_RESOURCE_HOST_DEB}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='m.coonen@${domain}'" "*respCostCenter='UM-30009999X'")

    # Contributor access for UM-SCANNEXUS
    ichmod -r write UM-SCANNEXUS /nlmumc/projects/${project}
    # Manage access for coonen
    ichmod -r own "m.coonen@${domain}" /nlmumc/projects/${project}
done

##########
## Special

# Create an initial collection folder for MDL data
irule -F /rules/projectCollection/createProjectCollection.r "*project='P000000010'" "*title='MDL placeholder collection'"
ichmod -r write "service-mdl" /nlmumc/projects/P000000010
# Add additional AVUs
imeta add -C /nlmumc/projects/P000000010/C000000001 creator irods_bootstrap@docker.dev
imeta add -C /nlmumc/projects/P000000010/C000000001 dcat:byteSize 0
imeta add -C /nlmumc/projects/P000000010/C000000001 numFiles 0

# Create an initial collection folder for HVC data
irule -F /rules/projectCollection/createProjectCollection.r "*project='P000000011'" "*title='HVC placeholder collection'"
ichmod -r write "service-mdl" /nlmumc/projects/P000000011
# Add additional AVUs
imeta add -C /nlmumc/projects/P000000011/C000000001 creator irods_bootstrap@docker.dev
imeta add -C /nlmumc/projects/P000000011/C000000001 dcat:byteSize 0
imeta add -C /nlmumc/projects/P000000011/C000000001 numFiles 0
