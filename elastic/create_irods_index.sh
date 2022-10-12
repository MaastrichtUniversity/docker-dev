#!/bin/bash

for EXPONENTIAL_BACKOFF in {1..10}; do
    nc -w 1 -z localhost 9200 && break;
    DELAY=$((2**$EXPONENTIAL_BACKOFF))
    echo "elastic not yet available, sleeping for $DELAY seconds"
    sleep $DELAY
done


curl -u elastic:$ELASTIC_PASSWORD -X GET "localhost:9200/_cluster/health?wait_for_status=green&timeout=300s&pretty" | grep green
# Wait 300 seconds for elastic to have status green
if ! [ $? -eq 0  ];then
    echo "Unable to connect to elastic"
    exit 1
fi

# Does the irods index already exist
curl -X GET -u elastic:$ELASTIC_PASSWORD localhost:9200/irods?pretty | grep -q 404

if [ $? -eq 0 ];then
  echo "Index irods does not exist, creating"
  curl -X PUT -u elastic:$ELASTIC_PASSWORD localhost:9200/irods?pretty
fi


