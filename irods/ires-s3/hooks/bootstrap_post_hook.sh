#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

# Update /etc/hosts file with help center url pointing to proxy ip address so it can be resolved in the container (only for dev)
echo "172.21.1.100 help.mdr.local.dh.unimaas.nl" >> /etc/hosts

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"
