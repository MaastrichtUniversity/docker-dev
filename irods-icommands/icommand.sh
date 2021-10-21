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
  "irods_client_server_negotiation": "request_server_negotiation",
  "irods_client_server_policy": "CS_NEG_REQUIRE",
  "irods_encryption_key_size": 32,
  "irods_encryption_salt_size": 8,
  "irods_encryption_num_hash_rounds": 16,
  "irods_encryption_algorithm": "AES-256-CBC"
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
