#!/usr/bin/env bash

############
## Resources

# Create coordination- and child-resources for project data
iadmin mkresc UM-Ceph-S3-GL s3 `hostname`:/dh-irods-bucket-dev \"S3_DEFAULT_HOSTNAME=minio2:9000;S3_AUTH_FILE=/var/lib/irods/minio2.keypair;S3_REGIONNAME=irods-dev;S3_RETRY_COUNT=1;S3_WAIT_TIME_SEC=3;S3_PROTO=HTTP;ARCHIVE_NAMING_POLICY=consistent;HOST_MODE=cacheless_attached;S3_CACHE_DIR=/cache\"
iadmin addchildtoresc replRescUMCeph01 UM-Ceph-S3-GL

# Add comment to resource for better identification in pacman's createProject dropdown
iadmin modresc ${HOSTNAME}Resource comment DO-NOT-USE

##########
## Special

