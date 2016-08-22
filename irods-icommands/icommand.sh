#!/usr/bin/env bash

# Set the specific user in irods_environment
cat << EOF > ~/.irods/irods_environment.json
{
  "irods_port": 1247,
  "irods_user_name": "$1@maastrichtuniversity.nl",
  "irods_host": "irods.local",
  "irods_zone_name": "nlmumc",
  "irods_cwd": "/nlmumc/projects",
  "irods_home": "/nlmumc/projects"
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
