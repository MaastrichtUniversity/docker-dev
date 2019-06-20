#!/bin/bash

set -e

source /etc/secrets

# Update RIT rules
# FYI: This step (and make of the microservices) rely on sequential starts of the ires-containers. If those containers
# start simultaneously, the make steps fail because they are accessing the same files at the same time.
# Now solved by letting ires_centos wait for ires:1248 in Dockerize
cd /rules && make

# Remove previous build dir (if exists)
if [ -d "/microservices/build" ]; then
  rm -fr /microservices/build
fi

# Update RIT microservices
mkdir -p /microservices/build && cd /microservices/build && cmake .. && make && make install

# Update RIT helpers
cp /helpers/* /var/lib/irods/msiExecCmd_bin/.

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "16s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_METADATA_CHANNEL ${MIRTH_METADATA_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MIRTH_VALIDATION_CHANNEL ${MIRTH_VALIDATION_CHANNEL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ 86400\,/' /etc/irods/server_config.json

    su - irods -c "/opt/irods/bootstrap_irods.sh"

    touch /var/run/irods_installed

else
    service irods start
fi

# Force start of Metalnx RMD
service rmd restart

#logstash
/etc/init.d/filebeat start

# Install iRODS S3 plugin
# Compile plugin from source:
#echo "download S3 plugin"
#cd /tmp
#git clone https://github.com/JustinKyleJames/irods_resource_plugin_s3
#cd /tmp/irods_resource_plugin_s3 && git checkout issue_1867
#echo "compiling iRODS S3 plugin"
#mkdir build && cd build && cmake /tmp/irods_resource_plugin_s3 && make package
#echo "Installing s3 dpkg"
#dpkg -i /tmp/irods_resource_plugin_s3/build/irods-resource-plugin-s3*.deb

# or use precompiled plugin
# based on https://github.com/JustinKyleJames/irods_resource_plugin_s3/commit/fccdc69d0b54642c77717ef67d52201479dc7a08
echo "Installing s3 dpkg"
dpkg -i /tmp/irods-resource-plugin-s3_2.5.0~xenial_amd64.deb

#Create secrets file
touch /var/lib/irods/minio1.keypair && chown irods /var/lib/irods/minio1.keypair && chmod 400 /var/lib/irods/minio1.keypair
echo "ABCDEFGHIJKLMNOPQRST" >  /var/lib/irods/minio1.keypair
echo "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEFGHIJKLMNO" >> /var/lib/irods/minio1.keypair

# Create cache dir for S3 plugin
mkdir /cache && chown irods /cache

# Add S3 resource
su - irods -c "iadmin mkresc replRescUMCeph01 replication"
su - irods -c "iadmin mkresc UM-Ceph-S3-AC s3 `hostname`:/dh-irods-bucket-dev \"S3_DEFAULT_HOSTNAME=minio1:9000;S3_AUTH_FILE=/var/lib/irods/minio1.keypair;S3_REGIONNAME=irods-dev;S3_RETRY_COUNT=1;S3_WAIT_TIME_SEC=3;S3_PROTO=HTTP;ARCHIVE_NAMING_POLICY=consistent;HOST_MODE=cacheless_attached;S3_CACHE_DIR=/cache\""
su - irods -c "iadmin addchildtoresc replRescUMCeph01 UM-Ceph-S3-AC"

# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*
