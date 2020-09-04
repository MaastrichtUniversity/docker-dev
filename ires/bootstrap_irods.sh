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

# Add storage pricing to resources
imeta add -R ${HOSTNAME}Resource NCIT:C88193 999
imeta add -R replRescUM01 NCIT:C88193 0.189

###########
## Projects and project permissions
domain="maastrichtuniversity.nl"

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.vanschayck@${domain}'" "*dataSteward='p.vanschayck@${domain}'" "*respCostCenter='UM-30001234X'" "*openAccess='false'" "*tapeArchive='true'")

    # Manage access
    ichmod -r own "p.vanschayck@${domain}" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "p.vanschayck@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write SRAM-M4I-Nanoscopy /nlmumc/projects/${project}

    # Viewer access
done

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='p.suppers@${domain}'" "*dataSteward='o.palmen@${domain}'" "*respCostCenter='UM-30009998X'" "*openAccess='false'" "*tapeArchive='true'")

    # Manage access
    ichmod -r own "p.suppers@${domain}" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "o.palmen@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write SRAM-DataHub /nlmumc/projects/${project}

    # Enable archiving for this project
    imeta set -C /nlmumc/projects/${project} enableArchive true
    # Enable export to Open Access for this project
    imeta set -C /nlmumc/projects/${project} enableOpenAccessExport true
    # Set the destination archive resource
    imeta set -C /nlmumc/projects/${project} archiveDestinationResource arcRescSURF01

    # Viewer access
done

for i in {01..1}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='(ScaNxs) ${PROJECTNAME}'" "*principalInvestigator='m.coonen@${domain}'" "*dataSteward='o.palmen@${domain}'" "*respCostCenter='UM-30009999X'" "*openAccess='false'" "*tapeArchive='true'")

    # Manage access
    ichmod -r own "m.coonen@${domain}" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "o.palmen@${domain}" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write SRAM-SCANNEXUS /nlmumc/projects/${project}

    # Viewer access
    ichmod -r read SRAM-DataHub /nlmumc/projects/${project}
done

##########
## Special
