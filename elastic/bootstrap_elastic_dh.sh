#!/bin/bash

/tmp/create_collection_metadata_index.sh &

/bin/tini -s /usr/local/bin/docker-entrypoint.sh

