#!/bin/bash

source /etc/irods/rodssync/bin/activate

export CELERY_BROKER_URL=redis://127.0.0.1:6379/0
export PYTHONPATH=`pwd`

echo $1
echo $2
echo $3

python -m irods_capability_automated_ingest.irods_sync start $1 $2 --event_handler $3 --synchronous --progress --ignore_cache --log_filename /tmp/ingest_put.log

if [ $? -eq 0 ]
then
  echo "The script ran ok"
  exit 0
else
  echo $?
  echo "The script failed" >&2
  exit 1
fi

deactivate
