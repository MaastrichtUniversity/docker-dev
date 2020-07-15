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


echo "Create Groups"
groupsJSON=$(cat /tmp/groups.json | jq -c '.')
echo $groupsJSON | jq  -r -c '.[]'  | while read groupJSON; do
  groupName=$(echo $groupJSON | jq -r -c '.name' )
  echo "groupName: $groupName"
  #for starters dont try to sync anything just create new groups if this group doesnt exist yet
  if (/opt/jboss/keycloak/bin/kcadm.sh get groups -r drupal | jq -c -r ".[] " | grep -q "rit" );
  then
     echo "GroupName ${groupName} already found in keycloak..."
  else
     /opt/jboss/keycloak/bin/kcadm.sh create groups -r drupal -b "{ \"name\": \"${groupName}\", \"attributes\": {\"gidNumber\":[\"999\"] } }"   
  fi
done
echo "Groups Created"


echo "Create Users"
usersJSON=$(cat /tmp/users.json | jq -c '.')#

echo $usersJSON | jq  -r -c '.[]'  | while read userJSON; do
  userID=$(echo $userJSON | jq -r -c '.userName' )
  displayName=$(echo $userJSON | jq -r -c '.displayName' )
  userEmail=$(echo $userJSON | jq -r -c '.email' )
  groupsMemberOf=$(echo $userJSON | jq -r -c '.memberOf' )
  echo "userName/id: $userID displayName: $displayName email: $userEmail"
  # Check if user already exists, if not create user and set password
  if (/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username="${userID}" | grep -q "id");
  then
    echo "user ${userID} already found in keycloak..."
  else
    keycloakUserID=$( /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username="${userID}" -s enabled=true -s email="${userEmail}" -s "attributes.displayName=${displayName}" -i )
    echo "created new user ${userID} with keycloakId: ${keycloakUserID}"
    #echo "setting now password... (for: ${userID})"
    /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username ${userID} --new-password 'foobar'
    #echo "done."

    #go through the list of group memberships and add the user to the correct group
    echo "$groupsMemberOf"
    echo $groupsMemberOf | jq -r -c '.[]' | while read groupName; do
       keycloakGroupID=$( /opt/jboss/keycloak/bin/kcadm.sh get groups -r drupal | jq -c -r ".[] " | grep "${groupName}" | jq -c -r ".id" )
       if [ -z $keycloakGroupID ]
       then
           echo "cant add user ${keycloakUserID} to ${groupName}, could not find group  in keycloak!"
       else
          echo "adding user ${keycloakUserID} to ${groupName} ($keycloakGroupID)"
          #https://www.keycloak.org/docs/latest/server_admin/#_group_operations
          /opt/jboss/keycloak/bin/kcadm.sh update users/${keycloakUserID}/groups/${keycloakGroupID} -r drupal
       fi 
    done
  fi
done
echo "Users Created"


# Trigger full sync of the ldap
# TODO: Is this needed?
echo "Full Sync LDAP"
/opt/jboss/keycloak/bin/kcadm.sh create user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync -r drupal

echo "Done syncing LDAP"

