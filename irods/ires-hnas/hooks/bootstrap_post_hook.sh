#!/bin/bash
#
# We create mock dev environment: mock projects and collections to test stuff against

echo "INFO: Executing bootstrap_irods.sh"
su irods -c "/opt/irods/hooks/bootstrap_irods.sh"
#mkdir -p /var/lib/irods/log/
#echo "hello" > /var/lib/irods/log/reLog.test.txt
#chmod -R 777 /var/lib/irods/log/
