#!/bin/bash
set -e

function retry {
  local retries=$1
  shift

  local count=0
  until "$@"; do
    exit=$?
    wait=$((2 ** $count))
    count=$(($count + 1))
    if [ $count -lt $retries ]; then
      echo "Retry $count/$retries exited $exit, retrying in $wait seconds..."
      sleep $wait
    else
      echo "Retry $count/$retries exited $exit, no more retries left."
      return $exit
    fi
  done
  return 0
}

echo "Starting import"
echo "starting" > /var/run/dh_import_state

echo $RIT_ENV

echo "Login"

retry 10 /opt/jboss/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user "$KEYCLOAK_USER" --password "$KEYCLOAK_PASSWORD"

echo "Disable SSL"
# Disable SSL for DEV
/opt/jboss/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE

echo "Set the correct DEV envonment"
# Set the correct DEV envonment
sed 's/RIT_ENV/'"$RIT_ENV"'/g' /tmp/realm-export.json > /tmp/realm-export_env.json

echo "Set the correct ldap admin password envonment"
# Set the correct ldap admin password envonment
sed 's/\*\*\*\*\*\*\*\*\*\*/'"$LDAP_ADMIN_PASSWORD"'/g'  /tmp/realm-export_env.json >  /tmp/realm-export_env_pw.json


# If django realm does not yet exist load it from config
if ! $(/opt/jboss/keycloak/bin/kcadm.sh get realms | grep -q "django");
then
  echo "Import Django realm"
  /opt/jboss/keycloak/bin/kcadm.sh create realms -f /tmp/realm-export_env_pw.json
fi

echo "Full Sync LDAP"
/opt/jboss/keycloak/bin/kcadm.sh create user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync -r django

echo "Setting password for Users"
usersJSON=$(cat /tmp/users.json | jq -c '.')


echo $usersJSON | jq  -r -c '.[]'  | while read userJSON; do
  userID=$(echo $userJSON | jq -r -c '.userName' )
  if (/opt/jboss/keycloak/bin/kcadm.sh get users -r django -q username="${userID}" | grep -q "id");
  then
     echo "Setting password for ${userID}"
     /opt/jboss/keycloak/bin/kcadm.sh set-password -r django --username ${userID} --new-password 'foobar'
  else
      echo "User not found, check make sure ldap and users.json match"
      exit 1
  fi
done

echo "Full Sync LDAP"
/opt/jboss/keycloak/bin/kcadm.sh create user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync -r django

echo "Done syncing LDAP"

# We use this as a quick way of doing (poor man's) orchestration
# See dh_is_ready.sh
echo "completed" > /var/run/dh_import_state
