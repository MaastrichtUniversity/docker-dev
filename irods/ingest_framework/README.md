## Howto run the dockerized irods ingest framework:

> **NOTE:**  Currently only works with USE_SAMBA=false in your irods.secrets.cfg

```
# Start redis
./rit.sh up redis

# Build ingest image
./rit.sh build irods-ingest

# Build ingest worker
./rit.sh build irods-ingest-worker

```

* Next create a mounted dropzone in MDR



```
# Start the ingest worker 
./rit.sh run --rm irods-ingest-worker -c 4

# Run an ingest job 
./rit.sh run --rm irods-ingest start /mnt/ingest/zones/{token from mounted dropzone} /nlmumc/home/rods/TEST_OF_THE_DAY --synchronous --progress

# Run ingest job with the event handler 
./rit.sh run --rm irods-ingest start /mnt/ingest/zones/{token from mounted dropzone} /nlmumc/home/rods/TEST_OF_THE_DAY --event_handler /var/lib/irods/event_handler.py --synchronous --progress --ignore_cache --log_filename /tmp/tuto_reg.log

```

## Run flask 

docker exec in the irods-ingest-worker container 
```
export FLASK_APP=/var/lib/irods/flask_app.py
flask run --host=0.0.0.0
curl localhost:5000/job -d '{"source": "/mnt/ingest/zones/{token from mounted dropzone}", "target": "/nlmumc/home/rods/TEST_OF_THE_DAY"}' -H 'Content-Type: application/json'
```