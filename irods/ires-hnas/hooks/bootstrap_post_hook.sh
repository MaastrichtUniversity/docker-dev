#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"
