#!/bin/bash
sleep 10
set -e

source /etc/secrets

# Python requirements
# Need to upgrade pip from 8.1.2 to 20.3.4
# But pip2 cannot be upgrade to a version above 21 because of EOL
pip install --upgrade "pip < 21.0"
pip install -r /rules/python/python_requirements.txt

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

    # PoC: patch setup_irods.py to accept SSL settings
    patch --dry-run -f /var/lib/irods/scripts/setup_irods.py /opt/irods/add_ssl_setting_at_setup.patch
    if [[ $? -ne 0 ]]; then
        echo "Patching scripts/setup_irods.py is not possible with our patch"
    else
        patch -f /var/lib/irods/scripts/setup_irods.py /opt/irods/add_ssl_setting_at_setup.patch
    fi

    # File names for keys and certificates differ from host to host
    sed -i "s/ires-s3.dh.local/$HOSTNAME/g" /etc/irods/setup_responses

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-tapeArchive

    # Add python rule engine to iRODS
    /opt/irods/add_rule_engine.py /etc/irods/server_config.json python 1

    # Add config variable to iRODS
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_URL ${EPICPID_URL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_USER ${EPICPID_USER}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_PASSWORD ${EPICPID_PASSWORD}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MDR_HANDLE_URL ${MDR_HANDLE_URL}

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
# remove deb package (installed in Dockerfile)
apt purge irods-resource-plugin-s3
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
