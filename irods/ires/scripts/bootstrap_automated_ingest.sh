# Setup virtual environment and install the automated ingest framework
pip install virtualenv --user
python -m virtualenv -p python3.10 /etc/irods/rodssync
source /etc/irods/rodssync/bin/activate
pip install irods_capability_automated_ingest

patch /etc/irods/rodssync/lib/python3.10/site-packages/irods_capability_automated_ingest/sync_actions.py /var/lib/irods/Add_failure_check.patch

set -e

export CELERY_BROKER_URL=redis://ingest-redis.dh.local:6379/0
echo $CELERY_BROKER_URL
export PYTHONPATH=`pwd`
celery -A irods_capability_automated_ingest.sync_task worker -l error -Q restart,path,file &

deactivate