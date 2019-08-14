#!/bin/bash

set -e

source /etc/secrets

# Update RIT rules
cd /rules && make

# Build RIT microservices
mkdir -p /tmp/microservices-build && \
    cd /tmp/microservices-build && \
    cmake /microservices && \
    make && \
    make install

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

    # Execution of irods_bootstrap.sh moved further down

    touch /var/run/irods_installed

else
    service irods start
fi

# Force start of Metalnx RMD
service rmd restart

# Logstash
/etc/init.d/filebeat start

# Remove the multiline comment tags to build the plugin from source
<<COMMENT
# Install iRODS S3 plugin
# Compile plugin from source:
BuildFromSource=true
echo "download S3 plugin"
cd /tmp
git clone https://github.com/irods/irods_resource_plugin_s3
cd /tmp/irods_resource_plugin_s3 && git checkout 4-2-stable
sed -i 's/4\.2\.6/4\.2\.5/' CMakeLists.txt
echo "compiling iRODS S3 plugin"
mkdir build && cd build && cmake /tmp/irods_resource_plugin_s3 && make package
echo "Installing built s3 dpkg"
dpkg -i /tmp/irods_resource_plugin_s3/build/irods-resource-plugin-s3*.deb
COMMENT

# Or use precompiled plugin based on https://github.com/irods/irods_resource_plugin_s3/commit/6a24dd8e3b0f68e50324a877d1cbd0fdca051a46
if [ "$BuildFromSource" != true ] ; then
    echo "Installing precompiled s3 dpkg"
    dpkg -i /tmp/irods-resource-plugin-s3_2.6.1~xenial_amd64.deb
fi

# Create secrets file
touch /var/lib/irods/minio.keypair && chown irods /var/lib/irods/minio.keypair && chmod 400 /var/lib/irods/minio.keypair
echo ${ENV_S3_ACCESS_KEY} >  /var/lib/irods/minio.keypair
echo ${ENV_S3_SECRET_KEY} >> /var/lib/irods/minio.keypair

# Create cache dir for S3 plugin
mkdir /cache && chown irods /cache

# iRODS bootstrap script must be executed after installing the S3 plugin
su irods -c "/opt/irods/bootstrap_irods.sh"     # su without "-" to preserve env vars in child script

# this script must end with a persistent foreground process
tail -F /var/lib/irods/log/rodsLog.*
