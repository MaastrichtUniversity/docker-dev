#!/bin/bash

/opt/ceph-container/bin/entrypoint.sh mon &

while ! netcat -z mon1 6789; do   
  sleep 0.1 # wait for 1/10 of the second before check again
done

echo "CEPH available!"

echo "Creating pool irods-dev"
ceph osd pool create irods-dev 64

echo "Creating authkey"
ceph auth get-or-create client.irods-dev osd 'allow rw pool=irods-dev' mon 'allow r' > /etc/ceph/client.irods-dev.keyring

echo "Done..."

while true
do
	sleep 1
done