#!/bin/bash

source /etc/irods/rodssync/bin/activate

export CELERY_BROKER_URL=redis://127.0.0.1:6379/0
export PYTHONPATH=`pwd`

echo $1
echo $2
python -m irods_capability_automated_ingest.irods_sync start $1 $2 --synchronous --progress --ignore_cache --log_filename /tmp/tuto_reg.log

deactivate
