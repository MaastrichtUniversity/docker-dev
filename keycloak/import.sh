#!/bin/bash

sleep 60

echo $RIT_ENV

echo "Login"

/opt/jboss/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user "$KEYCLOAK_USER" <<< "$KEYCLOAK_PASSWORD"

echo "Disable SSL"
# Disable SSL for DEV
/opt/jboss/keycloak/bin/kcadm.sh update realms/master -s sslRequired=NONE

echo "Set the correct DEV envonment"
# Set the correct DEV envonment
sed 's/RIT_ENV/'"$RIT_ENV"'/g' /tmp/realm-export.json > /tmp/realm-export_env.json

echo "Import Drupal realm"
/opt/jboss/keycloak/bin/kcadm.sh create realms -f /tmp/realm-export_env.json

echo "Create Users"
#Create Users
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=d.theunissen -s enabled=true -s email=d.theunissen@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username d.theunissen <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=p.vanschayck -s enabled=true -s email=p.vanschayck@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username p.vanschayck <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=m.coonen -s enabled=true -s email=m.coonen@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username m.coonen <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=r.niesten -s enabled=true -s email=r.niesten@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username r.niesten <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=r.brecheisen -s enabled=true -s email=r.brecheisen@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username r.brecheisen <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=jonathan.melius -s enabled=true -s email=jonathan.meliusn@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username jonathan.melius <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=k.heinen -s enabled=true -s email=k.heinen@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username k.heinen <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=s.nijhuis -s enabled=true -s email=s.nijhuis@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username s.nijhuis <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=p.suppers -s enabled=true -s email=p.suppers@maastrichtuniversity.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username p.suppers <<< 'foobar'
/opt/jboss/keycloak/bin/kcadm.sh create users -r drupal -s username=rick.voncken -s enabled=true -s email=rick.voncken@scannexus.nl
/opt/jboss/keycloak/bin/kcadm.sh set-password -r drupal --username rick.voncken <<< 'foobar'

