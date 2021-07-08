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


# If django realm does not yet exist load it from config
if ! $(/opt/jboss/keycloak/bin/kcadm.sh get realms | grep -q "django");
then
  echo "Import Django realm"
  /opt/jboss/keycloak/bin/kcadm.sh create realms -f /tmp/realm-export_env_pw.json
fi


echo "Create Groups"
groupsJSON=$(cat /tmp/groups.json | jq -c '.')
echo $groupsJSON | jq  -r -c '.[]'  | while read groupJSON; do
  #the groups.json containes all kinds of information
  #but note that most of this should actually belong to COs (o) under dc=ordered 
  #which we cant manage vie keycloak. Only the cn and the uniqueIdetntifier are part of groups.
  #Even description and displayName are not the same as for COs
  uniqueIdentifier=$(echo  $groupJSON | jq -r -c '.uniqueIdentifier' )
  cn=$(echo  $groupJSON | jq -r -c '.cn' )
  #o=$(echo  $groupJSON | jq -r -c '.o' )
  #groupName=$(echo $groupJSON | jq -r -c '.name' ) 
  #displayName=$(echo $groupJSON | jq -r -c '.displayName' )
  #description=$(echo $groupJSON | jq -r -c '.description' )
  echo "group/cn: $cn"
  #for starters dont try to sync anything just create new groups if this group doesnt exist yet
  if (/opt/jboss/keycloak/bin/kcadm.sh get groups -r django | jq -c -r ".[] " | grep -q "\"$cn\"" );
  then
     echo "Group ${cn} already found in keycloak..."
  else
     /opt/jboss/keycloak/bin/kcadm.sh create groups -r django -b "{ \"name\": \"${cn}\", \"attributes\": {\"uniqueIdentifier\":[\"$uniqueIdentifier\"] } }"
  fi
done
echo "Groups Created"


echo "Create Users"
usersJSON=$(cat /tmp/users.json | jq -c '.')
#echo $usersJSON

echo $usersJSON | jq  -r -c '.[]'  | while read userJSON; do
  userID=$(echo $userJSON | jq -r -c '.userName' )
  displayName=$(echo $userJSON | jq -r -c '.displayName' )
  userEmail=$(echo $userJSON | jq -r -c '.email' )
  lastName=$(echo $userJSON | jq -r -c '.lastName' )
  firstName=$(echo $userJSON | jq -r -c '.firstName' )
  eduPersonUniqueId=$(echo $userJSON | jq -r -c '.eduPersonUniqueId' )
  voPersonExternalID=$(echo $userJSON | jq -r -c '.voPersonExternalID' )
  voPersonExternalAffiliation=$(echo $userJSON | jq -r -c '.voPersonExternalAffiliation' )
  groupsMemberOf=$(echo $userJSON | jq -r -c '.memberOf' )
  echo "userName/id: $userID displayName: $displayName email: $userEmail"
  #echo "eduPersonUniqueId: $eduPersonUniqueId, voPersonExternalID: $voPersonExternalID, voPersonExternalAffiliation: $voPersonExternalAffiliation"
  # Check if user already exists, if not create user and set password
  if (/opt/jboss/keycloak/bin/kcadm.sh get users -r django -q username="${userID}" | grep -q "id");
  then
    echo "user ${userID} already found in keycloak..."
  else
    keycloakUserID=$( /opt/jboss/keycloak/bin/kcadm.sh create users -r django -s username="${userID}" -s enabled=true -s email="${userEmail}" -s lastName="${lastName}" -s firstName="${firstName}" -s "attributes.displayName=${displayName}" -s "attributes.eduPersonUniqueId=${eduPersonUniqueId}"  -s "attributes.voPersonExternalID=${voPersonExternalID}"  -s "attributes.voPersonExternalAffiliation=${voPersonExternalAffiliation}"  -i )
    echo "created new user ${userID} with keycloakId: ${keycloakUserID}"
    #echo "setting now password... (for: ${userID})"
    /opt/jboss/keycloak/bin/kcadm.sh set-password -r django --username ${userID} --new-password 'foobar'
    #echo "done."

    #go through the list of group memberships and add the user to the correct group
    echo "$groupsMemberOf"
    echo $groupsMemberOf | jq -r -c '.[]' | while read groupName; do
       keycloakGroupID=$( /opt/jboss/keycloak/bin/kcadm.sh get groups -r django | jq -c -r ".[] " | grep "\"${groupName}\"" | jq -c -r ".id" )
       echo "groupId in keycloak: $keycloakGroupID"
       if [ -z "$keycloakGroupID" ]
       then
           echo "cant add user ${keycloakUserID} to ${groupName}, could not find group  in keycloak!"
       else
          echo "adding user ${keycloakUserID} to ${groupName} ($keycloakGroupID)"
          echo "$keycloakGroupID"
          #https://www.keycloak.org/docs/latest/server_admin/#_group_operations
          /opt/jboss/keycloak/bin/kcadm.sh update "users/${keycloakUserID}/groups/${keycloakGroupID}" -r django
       fi 
    done
  fi
done
echo "Users Created"


# Trigger full sync of the ldap
# TODO: Is this needed?
echo "Full Sync LDAP"
/opt/jboss/keycloak/bin/kcadm.sh create user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync -r django

echo "Done syncing LDAP"

