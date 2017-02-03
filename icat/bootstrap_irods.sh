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
iadmin mkresc UM-hnas-4k unixfilesystem ires:/mnt/UM-hnas-4k
iadmin mkresc UM-hnas-4k-repl unixfilesystem ires:/mnt/UM-hnas-4k-repl
iadmin addchildtoresc replRescUM01 UM-hnas-4k
iadmin addchildtoresc replRescUM01 UM-hnas-4k-repl

# Ideally, the AZM resource is not needed for production. Included here to test concept of the policy choosing proper resource for a project
iadmin mkresc replRescAZM01 replication
iadmin mkresc AZM-storage unixfilesystem ires:/mnt/AZM-storage
iadmin mkresc AZM-storage-repl unixfilesystem ires:/mnt/AZM-storage-repl
iadmin addchildtoresc replRescAZM01 AZM-storage
iadmin addchildtoresc replRescAZM01 AZM-storage-repl

##############
## Collections
imkdir -p /nlmumc/ingest/zones
imkdir -p /nlmumc/ingest/shares/rawdata
imkdir -p /nlmumc/projects

########
## Users
users="p.vanschayck m.coonen d.theunissen p.suppers rbg.ravelli g.tria p.ahles delnoy"
domain="maastrichtuniversity.nl"

for user in $users; do
    iadmin mkuser "${user}@${domain}" rodsuser
    iadmin moduser "${user}@${domain}" password foobar
done

serviceUsers="service-dropzones service-mdl"

for user in $serviceUsers; do
    iadmin mkuser "${user}" rodsuser
    iadmin moduser "${user}" password foobar
done

#########
## Groups
nanoscopy="p.vanschayck g.tria rbg.ravelli"

iadmin mkgroup nanoscopy-l
for user in $nanoscopy; do
    iadmin atg nanoscopy-l "${user}@${domain}"
done

rit="p.vanschayck m.coonen d.theunissen p.suppers delnoy"

iadmin mkgroup rit-l
for user in $rit; do
    iadmin atg rit-l "${user}@${domain}"
done

##############
## Permissions

# Make sure that all users (=members of group public) can browse to directories for which they have rights
ichmod read public /nlmumc
ichmod read public /nlmumc/projects

# Give groups access to the ingestZone
ichmod -r own nanoscopy-l /nlmumc/ingest/zones
ichmod -r own rit-l /nlmumc/ingest/zones

###########
## Projects and project permissions

for i in {01..4}; do
    project=$(irule -F /rules/projects/createProject.r)
    # AVU's for collections
    imeta set -C /nlmumc/projects/${project} ingestResource ${IRODS_RESOURCE_HOST}Resource
    imeta set -C /nlmumc/projects/${project} resource replRescAZM01
    imeta set -C /nlmumc/projects/${project} title "`fortune | head -n 1`"

    # Contributor access for RIT
    ichmod -r write rit-l /nlmumc/projects/${project}
    # Manage access for suppers
    ichmod -r own "p.suppers@${domain}" /nlmumc/projects/${project}
done

for i in {01..2}; do
    project=$(irule -F /rules/projects/createProject.r)
    # AVU's for collections
    imeta set -C /nlmumc/projects/${project} ingestResource ${IRODS_RESOURCE_HOST}Resource
    imeta set -C /nlmumc/projects/${project} resource replRescUM01
    imeta set -C /nlmumc/projects/${project} title "`fortune | head -n 1`"

    # Contributor access for nanoscopy
    ichmod -r write nanoscopy-l /nlmumc/projects/${project}
    # Manage access for Paul
    ichmod -r own "p.vanschayck@${domain}" /nlmumc/projects/${project}
done

for i in {01..8}; do
    project=$(irule -F /rules/projects/createProject.r)
    # AVU's for collections
    imeta set -C /nlmumc/projects/${project} ingestResource ${IRODS_RESOURCE_HOST}Resource
    imeta set -C /nlmumc/projects/${project} resource replRescUM01
    imeta set -C /nlmumc/projects/${project} title "`fortune | head -n 1`"

    # Read access for rit
    ichmod -r read rit-l /nlmumc/projects/${project}
done


##########
## Special

# Create an initial collection folder for MDL data
imkdir /nlmumc/projects/P000000001/C000000001
ichmod -r write "service-mdl@${domain}" /nlmumc/projects/P000000001
