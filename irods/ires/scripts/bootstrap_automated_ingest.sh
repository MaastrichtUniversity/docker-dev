# Setup virtual environment and install the automated ingest framework
pip install virtualenv --user
python -m virtualenv -p python3.10 /etc/irods/rodssync
source /etc/irods/rodssync/bin/activate
pip install irods_capability_automated_ingest

export CELERY_BROKER_URL=redis://127.0.0.1:6379/0
export PYTHONPATH=`pwd`
celery -A irods_capability_automated_ingest.sync_task worker -l error -Q restart,path,file &

deactivate