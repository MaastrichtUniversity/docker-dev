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

echo "Create Users"
#Create Users


#if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=d.theunissen  | grep -q "id");
#then
#  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=d.theunissen -s enabled=true -s email=d.theunissen@maastrichtuniversity.nl
#  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username d.theunissen --new-password 'foobar'
#fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=p.vanschayck  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=p.vanschayck -s enabled=true -s email=p.vanschayck@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username p.vanschayck --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=m.coonen  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=m.coonen -s enabled=true -s email=m.coonen@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username m.coonen --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=r.niesten  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=r.niesten -s enabled=true -s email=r.niesten@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username r.niesten --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=r.brecheisen  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=r.brecheisen -s enabled=true -s email=r.brecheisen@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username r.brecheisen --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=jonathan.melius  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=jonathan.melius -s enabled=true -s email=jonathan.meliusn@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username jonathan.melius --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=k.heinen  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=k.heinen -s enabled=true -s email=k.heinen@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username k.heinen --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=s.nijhuis  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=s.nijhuis -s enabled=true -s email=s.nijhuis@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username s.nijhuis --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=p.suppers  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=p.suppers -s enabled=true -s email=p.suppers@maastrichtuniversity.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username p.suppers --new-password 'foobar'
fi

if ! $(/opt/jboss/keycloak/bin/kcadm.sh get users -r drupal -q username=rick.voncken  | grep -q "id");
then
  /opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=rick.voncken -s enabled=true -s email=rick.voncken@scannexus.nl
  /opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username rick.voncken --new-password 'foobar'
fi

echo "Users Created"

# Sync of the ldap 

echo "Syncing LDAP"
/opt/jboss/keycloak/bin/kcadm.sh create user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync -r drupal

echo "Done syncing LDAP"

