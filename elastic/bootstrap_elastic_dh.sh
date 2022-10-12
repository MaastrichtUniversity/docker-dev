#!/bin/bash

/tmp/create_irods_index.sh &

/bin/tini -s /usr/local/bin/docker-entrypoint.sh

