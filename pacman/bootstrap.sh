#!/bin/bash

cd /var/www/html/sites/all/modules/pacman && composer update

cd /var/www/html/sites/all/modules/rit_faker && composer update

cd /var/www/html/sites/all/modules/handsontable && yarn install

cd /var/www/html/sites/all/modules/islandora_ontology_autocomplete && yarn install

# Only re-install when in a fresh container
if [[ ! -e /var/www/html/sites/default/settings.php ]]; then
    cd /var/www/html && drush site-install \
        --db-url=mysql://root:foobar@db:3306/pacman \
        --yes \
        --account-name=rit-admin \
        --account-pass=foobar \
        --site-name=pacman
fi

cd /var/www/html && drush en \
    --yes \
    xml_forms \
    pacman \
    handsontable \
    rit_forms \
    fhml_um \
    islandora_xml_form_builder_states \
    islandora_ontology_autocomplete \
    islandora_crossref_lookup \
    jquery_update \
    rit_faker \
    rit_landing_page

cd /var/www/html && drush add-rit-forms

domain=maastrichtuniversity.nl

cd /var/www/html && drush user-create p.vanschayck --mail="p.vanschayck@${domain}" --password="foobar"
cd /var/www/html && drush user-create m.coonen --mail="m.coonen@${domain}" --password="foobar"
cd /var/www/html && drush user-create d.theunissen --mail="d.theunissen@${domain}" --password="foobar"
cd /var/www/html && drush user-create r.niesten --mail="r.niesten@${domain}" --password="foobar"
cd /var/www/html && drush user-create p.suppers --mail="p.suppers@${domain}" --password="foobar"
cd /var/www/html && drush user-create r.brecheisen --mail="r.brecheisen@${domain}" --password="foobar"
cd /var/www/html && drush user-create stijn.hanssen --mail="stijn.hanssen@${domain}" --password="foobar"
cd /var/www/html && drush user-create jonathan.melius --mail="jonathan.melius@${domain}" --password="foobar"

# Set homepage to pacman/info
cd /var/www/html && drush vset site_frontpage pacman/info

# Set timezone to Europe/Amsterdam
drush vset date_default_timezone 'Europe/Amsterdam' -y

# Set drupal to know of the reverse proxy used in docker
drush vset reverse_proxy 'TRUE'
proxyip=$(getent hosts proxy | awk '{ print $1 }')
php -r "echo json_encode(array('$proxyip'));"  | drush vset --format=json reverse_proxy_addresses -

# Enable and make theme default
cd /var/www/html && drush vset theme_default fhml_um

apache2-foreground
