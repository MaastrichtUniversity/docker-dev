#!/usr/bin/env bash

############
## Resources

#Add comment to resource for better identification in dropdown
iadmin modresc iresResource comment UBUNTU-INGEST-RESOURCE

##########
## Special

# Mounted collection for rawdata
# imcoll -m filesystem /mnt/ingest/shares/rawData /nlmumc/ingest/shares/rawdata