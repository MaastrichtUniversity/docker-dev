#!/usr/bin/env bash

# The rods user does not have a domain
if [[ $1 == "rods" ]] || [[ $1 == *"service-"* ]]; then
    user=$1
else
    user="${1}@maastrichtuniversity.nl"
fi

# Set the specific user in irods_environment
cat << EOF > ~/.irods/irods_environment.json
{
  "irods_port": 1247,
  "irods_user_name": "${user}",
  "irods_host": "irods.dh.local",
  "irods_zone_name": "nlmumc",
  "irods_cwd": "/nlmumc/projects",
  "irods_home": "/nlmumc/projects",
  "irods_ssl_ca_certificate_file": "/opt/irods_ssl/server.crt"
}
EOF

if [[ $1 == "rods" ]]; then
    iinit irods
else
    # All user accounts have the password foobar in development
    iinit foobar
fi

# Remove first argument
shift

# Execute rest of arguments as command
exec "$@"
