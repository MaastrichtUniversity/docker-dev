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
iadmin modresc ${HOSTNAME}Resource comment UM-UBUNTU-INGEST-RESOURCE
iadmin modresc replRescUM01 comment Replicated-resource-for-UM

# Add storage pricing to resources
imeta add -R ${HOSTNAME}Resource NCIT:C88193 999
imeta add -R replRescUM01 NCIT:C88193 0.130

###########
## Projects and project permissions

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='pvanschay2'" "*dataSteward='pvanschay2'" "*respCostCenter='UM-30001234X'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'")

    # Manage access
    ichmod -r own "pvanschay2" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "pvanschay2" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write m4i-nanoscopy /nlmumc/projects/${project}

    # Viewer access
done

for i in {01..2}; do
    PROJECTNAME=$(fortune | head -n 1 | sed 's/\x27/ /g')
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='${PROJECTNAME}'" "*principalInvestigator='psuppers'" "*dataSteward='opalmen'" "*respCostCenter='UM-30009998X'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'")

    # Manage access
    ichmod -r own "psuppers" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write datahub /nlmumc/projects/${project}

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
    project=$(irule -F /rules/projects/createProject.r "*authorizationPeriodEndDate='1-1-2018'" "*dataRetentionPeriodEndDate='1-1-2018'" "*ingestResource='${HOSTNAME}Resource'" "*resource='replRescUM01'" "*storageQuotaGb='10'" "*title='(ScaNxs) ${PROJECTNAME}'" "*principalInvestigator='mcoonen'" "*dataSteward='opalmen'" "*respCostCenter='UM-30009999X'" "*openAccess='false'" "*tapeArchive='true'" "*tapeUnarchive='true'")

    # Manage access
    ichmod -r own "mcoonen" /nlmumc/projects/${project}

    # Data Steward gets manager rights
    ichmod -r own "opalmen" /nlmumc/projects/${project}

    # Contributor access
    ichmod -r write scannexus /nlmumc/projects/${project}

    # Viewer access
    ichmod -r read datahub /nlmumc/projects/${project}
done

##########
## Special
