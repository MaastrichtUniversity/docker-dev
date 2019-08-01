#!/usr/bin/env bash

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc UM-hnas-4k unixfilesystem ${HOSTNAME}:/mnt/UM-hnas-4k
iadmin mkresc UM-hnas-4k-repl unixfilesystem ${HOSTNAME}:/mnt/UM-hnas-4k-repl
iadmin mkresc replRescUM01 replication
iadmin addchildtoresc replRescUM01 UM-hnas-4k
iadmin addchildtoresc replRescUM01 UM-hnas-4k-repl

# Add comment to resource for better identification in pacman's createProject dropdown
iadmin modresc ${HOSTNAME}Resource comment UBUNTU-INGEST-RESOURCE
iadmin modresc replRescUM01 comment Replicated-resource-for-UM

###########
## Projects and project permissions
domain="maastrichtuniversity.nl"

# TODO: Make createProject rule compatible with simultaneous execution (see createProjectCollection retry mechanism for inspiration)
for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.vanschayck@${domain}'" "*respCostCenter='UM-30001234X'" "*pricePerGBPerYear='0.32'")

    # Manage access
    ichmod -r own "p.vanschayck@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write nanoscopy-l /nlmumc/projects/${project}

    # Viewer access
done

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.suppers@${domain}'" "*respCostCenter='UM-30009998X'" "*pricePerGBPerYear='0.24'")

    # Manage access
    ichmod -r own "p.suppers@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write rit-l /nlmumc/projects/${project}

    # Viewer access
done

for i in {01..1}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='(ScaNxs) ${PROJECTNAME}'" "*principalInvestigator='m.coonen@${domain}'" "*respCostCenter='UM-30009999X'" "*pricePerGBPerYear='0.32'")

    # Manage access
    ichmod -r own "m.coonen@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write UM-SCANNEXUS /nlmumc/projects/${project}

    # Viewer access
    ichmod -r read rit-l /nlmumc/projects/${project}
done

##########
## Special
