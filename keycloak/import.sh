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


# If drupal realm does not yet exist load it from config
if ! $(/opt/jboss/keycloak/bin/kcadm.sh get realms | grep -q "drupal");
then
  echo "Import Drupal realm"
  /opt/jboss/keycloak/bin/kcadm.sh create realms -f /tmp/realm-export_env_pw.json
fi

# Create Users
echo "Create Users"

# Maastrichtuniversity
usersJSON=$(cat /tmp/users.json | jq -c '.')

echo $usersJSON | jq  -c '.[]'  | while read userJSON; do
  userID="$(echo $userJSON | jq -c '.userName' )"  
  displayName="$(echo $userJSON | jq -c '.displayName' )"
  userEmail="$(echo $userJSON | jq -c '.email' )"

  echo "userName/id: $userID displayName: $displayName email: $userEmail"
  # Check if user already exists, if not create user and set password
  if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username="${userID}"  | grep -q "id");
  then
    /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username="${userID}" -s enabled=true -s email="${userEmail}" -s "attributes.displayName=${displayName}"
    #echo "setting now password... (for: ${userID})"
    #/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username "${userID}" --new-password 'foobar'
    #echo "done."
  else
    echo "user ${userID} already found in keycloak..."
  fi
done

# Scannexus
scannexus="rick.voncken"

for user in $scannexus; do
  # Check if user already exists, if not create user and set password
  if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username="${user}"  | grep -q "id");
  then
    /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username="${user}" -s enabled=true -s email="${user}"@scannexus.nl
    /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username "${user}" --new-password 'foobar'
  fi
done

echo "Users Created"

# Trigger full sync of the ldap
# TODO: Is this needed?
echo "Full Sync LDAP"
/opt/jboss/keycloak/bin/kcadm.sh create user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync -r drupal

echo "Done syncing LDAP"

