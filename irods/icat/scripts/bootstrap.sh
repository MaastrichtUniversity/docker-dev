#!/bin/bash

debug_on_pattern='^(true|yes|1)$'
PS4='$0:$LINENO: '
if [[ "${DEBUG_DH_BOOTSTRAP,,}" =~ $debug_on_pattern ]]; then
    set -x
fi

set -e

# This script (bootsrap.sh) is specified to be run like so in the Dockerfile:
#    ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
# This means (square brakets) it will be exec'ed, so it will take PID 1 in the
# pertinenent PID namespace for this container.
# Linux treats PID 1 process differently. For example, for SIGTERM, it they
# haven't defined their own signal handler, signal is just ignored. So:
# Goal: make 'docker-compose down' fast (otherwise it waits 10s before SIGKILL)

trap _trap_sigterm SIGTERM

_trap_sigterm() {
    echo "$0: Caught SIGTERM! Exiting.."
    exit
}

until psql -h irods-db.dh.local -U postgres -c '\l'; do
    >&2 echo "Postgres is unavailable - sleeping"
    sleep 1
done

# Update RIT rules
cd /rules && make

# Build RIT microservices
mkdir -p /tmp/microservices-build && \
    cd /tmp/microservices-build && \
    cmake /microservices && \
    make && \
    make install

# Check if this is a first run of this container
if [[ ! -e /var/run/irods_installed ]]; then

    if [ -n "$RODS_PASSWORD" ]; then
        echo "Setting irods password"
        sed -i "23s/.*/$RODS_PASSWORD/" /etc/irods/setup_responses
    fi

    # set up the iCAT database
    /opt/irods/setupdb.sh /etc/irods/setup_responses

    # PoC: patch setup_irods.py to accept SSL settings
    patch --dry-run -f /var/lib/irods/scripts/setup_irods.py /opt/irods/patch/add_ssl_setting_at_setup.patch
    if [[ $? -ne 0 ]]; then
        echo "Patching scripts/setup_irods.py is not possible with our patch"
    else
        patch -f /var/lib/irods/scripts/setup_irods.py /opt/irods/patch/add_ssl_setting_at_setup.patch
    fi

    # set up iRODS
    python /var/lib/irods/scripts/setup_irods.py < /etc/irods/setup_responses

    # Add the ruleset-rit to server config
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-policies
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-misc
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-ingest
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projects
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-projectCollection
    /opt/irods/prepend_ruleset.py /etc/irods/server_config.json rit-tapeArchive

    # Not required here. Covered by irods-ruleset/misc/policies.r:acPreConnect
    #sed -i 's/CS_NEG_DONT_CARE/CS_NEG_REQUIRE/g' /etc/irods/core.re

    # Add python rule engine to iRODS
    /opt/irods/add_rule_engine.py /etc/irods/server_config.json python 1

    # Add config variable to iRODS
    # NOTE: These lines are added to the server_config.json, but only go into effect when restarting the irods service!
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_INGEST_REMOVE_DELAY ${IRODS_INGEST_REMOVE_DELAY}
    /opt/irods/add_env_var.py /etc/irods/server_config.json IRODS_TEMP_PASSWORD_LIFETIME ${IRODS_TEMP_PASSWORD_LIFETIME}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_URL ${EPICPID_URL}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_USER ${EPICPID_USER}
    /opt/irods/add_env_var.py /etc/irods/server_config.json EPICPID_PASSWORD ${EPICPID_PASSWORD}
    /opt/irods/add_env_var.py /etc/irods/server_config.json MDR_HANDLE_URL ${MDR_HANDLE_URL}

    # Dirty temp.password workaround
    sed -i 's/\"default_temporary_password_lifetime_in_seconds\"\:\ 120\,/\"default_temporary_password_lifetime_in_seconds\"\:\ '$IRODS_TEMP_PASSWORD_LIFETIME'\,/' /etc/irods/server_config.json

    # SURFsara Archive vault
    mkdir -p /mnt/SURF-Archive
    chown irods:irods /mnt/SURF-Archive

    # Python requirements
    # Need to upgrade pip from 8.1.2 to 20.3.4
    # But pip2 cannot be upgrade to a version above 21 because of EOL
    su irods -c "pip install --user --upgrade \"pip < 21.0\""
    su irods -c "pip install --user -r /rules/python/python_requirements.txt"

    su irods -c "/opt/irods/bootstrap_irods.sh"

    # Change default resource to rootResc for irods-user
    sed -i 's/\"irods_default_resource\"\:\ \"demoResc\"\,/\"irods_default_resource\"\:\ \"rootResc\"\,/' /var/lib/irods/.irods/irods_environment.json

    touch /var/run/irods_installed

else
    service irods start
fi

#logstash
/etc/init.d/filebeat start

# this script must end with a persistent foreground process
# 'wait' will avoid bash behavior of ignoring signal traps if a child process
# is running. See: https://stackoverflow.com/a/49511035/13203944
tail -F /var/lib/irods/log/rodsLog.* /var/lib/irods/log/reLog.* &
wait $!