#!/bin/bash
set -ex

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

# If drupal realm does not yet exist load it from config
if ! $(/opt/jboss/keycloak/bin/kcadm.sh get realms | grep -q "drupal");
then
  echo "Import Drupal realm"
  /opt/jboss/keycloak/bin/kcadm.sh create realms -f /tmp/realm-export_env.json
fi

#Create Users
echo "Create Users"
# Maastrichtuniversity
rit="p.vanschayck m.coonen d.theunissen p.suppers delnoy r.niesten r.brecheisen jonathan.melius k.heinen s.nijhuis"

for user in $rit; do
  # Check if user already exists, if not create user and set password
  if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username="${user}"  | grep -q "id");
  then
    /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username="${user}" -s enabled=true -s email="${user}"@maastrichtuniversity.nl
    /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username "${user}" --new-password 'foobar'
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
