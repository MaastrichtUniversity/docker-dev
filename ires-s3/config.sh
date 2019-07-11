#!/bin/bash

# config.sh
# Configures iRODS using the response values in /etc/irods/setup_responses
#

RESPFILE=$1

/var/lib/irods/packaging/setup_irods.sh < $1
