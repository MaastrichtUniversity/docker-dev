#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

# Mock dev env: SURFsara Archive vault
# NOTE: bootstrap_irods.sh depends on "/mnt/SURF-Archive"
echo "INFO: Creating SURF-Archive and putting mocked archiving rules in place"
mkdir -p /mnt/SURF-Archive
chown irods:irods /mnt/SURF-Archive
cp /opt/irods/DMFS/* /var/lib/irods/msiExecCmd_bin/
chmod 755 /var/lib/irods/msiExecCmd_bin/dm*

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"
