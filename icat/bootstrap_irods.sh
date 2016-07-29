#!/usr/bin/env bash

############
## Resources

# TO DO: composable resources with a default passthru rootResc resource as described here:
#        https://docs.irods.org/4.1.8/manual/best_practices/
iadmin mkresc UM-hnas-4k unixfilesystem ires:/mnt/UM-hnas-4k
iadmin mkresc UM-hnas-32k unixfilesystem ires:/mnt/UM-hnas-32k

##############
## Collections
imkdir -p /nlmumc/ingest/zones
imkdir -p /nlmumc/ingest/shares/rawdata
imkdir -p /nlmumc/projects

###########
## Projects
for i in {01..15}; do
    imkdir -p /nlmumc/projects/MUMC-MDL-000${i}
    # Resource for collections
    imeta add -C /nlmumc/projects/MUMC-MDL-000${i} resource UM-hnas-4k
    # Inheritance
    ichmod -r inherit /nlmumc/projects/MUMC-MDL-000${i}
done

for i in {01..16}; do
    imkdir -p /nlmumc/projects/MUMC-RIT-000${i}
    # Resource for collections
    imeta add -C /nlmumc/projects/MUMC-RIT-000${i} resource UM-hnas-4k
    ichmod -r inherit /nlmumc/projects/MUMC-RIT-000${i}
done

for i in {01..23}; do
    imkdir -p /nlmumc/projects/MUMC-M4I-000${i}
    # Resource for collections
    imeta add -C /nlmumc/projects/MUMC-M4I-000${i} resource UM-hnas-32k
    ichmod -r inherit /nlmumc/projects/MUMC-M4I-000${i}
done

for i in {01..42}; do
    imkdir -p /nlmumc/projects/MUMC-PATH-000${i}
    # Resource for collections
    imeta add -C /nlmumc/projects/MUMC-PATH-000${i} resource UM-hnas-4k
    ichmod -r inherit /nlmumc/projects/MUMC-PATH-000${i}
done

########
## Users
users="p.vanschayck m.coonen d.theunissen p.suppers rbg.ravelli g.tria p.ahles"

for user in $users; do
    iadmin mkuser $user rodsuser
    iadmin moduser $user password foobar
done

#########
## Groups
nanoscopy="p.vanschayck g.tria rbg.ravelli"

iadmin mkgroup nanoscopy-l
for user in $nanoscopy-l; do
    iadmin atg nanoscopy-l $user
done

rit="p.vanschayck m.coonen d.theunissen p.suppers"

iadmin mkgroup rit-l
for user in $rit-l; do
    iadmin atg rit-l $user
done

##############
## Permissions

# Make sure that all users (=members of group public) can browse to directories for which they have rights
ichmod read public /nlmumc
ichmod read public /nlmumc/projects

# Give groups access to the ingestZone
ichmod -r own nanoscopy-l /nlmumc/ingest/zones
ichmod -r own rit-l /nlmumc/ingest/zones

# Projects contributors
for i in {01..16}; do
    ichmod -r write rit-l /nlmumc/projects/MUMC-RIT-000${i}

done

for i in {01..23}; do
    ichmod -r write nanoscopy-l /nlmumc/projects/MUMC-M4I-000${i}
done

# Project viewers
for i in {01..42}; do
    ichmod -r read rit-l /nlmumc/projects/MUMC-PATH-000${i}
done

# Project managers
for i in {01..16}; do
    ichmod -r own p.suppers /nlmumc/projects/MUMC-RIT-000${i}
done

for i in {01..23}; do
    ichmod -r own p.vanschayck /nlmumc/projects/MUMC-M4I-000${i}
done


##########
## Special

# Mounted collection for rawdata
imcoll -m filesystem /mnt/ingest/shares/rawData /nlmumc/ingest/shares/rawdata