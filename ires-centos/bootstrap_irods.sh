#!/usr/bin/env bash

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc AZM-storage unixfilesystem ${HOSTNAME}:/mnt/AZM-storage
iadmin mkresc AZM-storage-repl unixfilesystem ${HOSTNAME}:/mnt/AZM-storage-repl
iadmin mkresc replRescAZM01 replication
iadmin addchildtoresc replRescAZM01 AZM-storage
iadmin addchildtoresc replRescAZM01 AZM-storage-repl

# Add comment to resource for better identification in pacman's createProject dropdown
iadmin modresc ${HOSTNAME}Resource comment CENTOS-INGEST-RESOURCE
iadmin modresc replRescAZM01 comment Replicated-resource-for-AZM

###########
## Projects and project permissions
domain="maastrichtuniversity.nl"

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescAZM01'" "*storageQuotaGb='10'" "*title='(azM) ${PROJECTNAME}'" "*principalInvestigator='m.coonen@${domain}'" "*respCostCenter='AZM-123456'" "*pricePerGBPerYear='0.32'")

    # Manage access
    ichmod -r own "m.coonen@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write rit-l /nlmumc/projects/${project}

    # Viewer access
done

##########
## Special

