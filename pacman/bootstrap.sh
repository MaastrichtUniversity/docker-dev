#!/bin/bash

cd /var/www/html/sites/all/modules/pacman && composer update

cd /var/www/html/sites/all/modules/rit_faker && composer update

cd /var/www/html/sites/all/modules/handsontable && bower install --allow-root

cd /var/www/html/sites/all/modules/islandora_ontology_autocomplete && bower install --allow-root

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
    rit_faker

cd /var/www/html && drush add-rit-forms

domain=maastrichtuniversity.nl

cd /var/www/html && drush user-create p.vanschayck --mail="p.vanschayck@${domain}" --password="foobar"
cd /var/www/html && drush user-create m.coonen --mail="m.coonen@${domain}" --password="foobar"
cd /var/www/html && drush user-create d.theunissen --mail="d.theunissen@${domain}" --password="foobar"
cd /var/www/html && drush user-create p.suppers --mail="p.suppers@${domain}" --password="foobar"

# Set homepage to pacman/info
cd /var/www/html && drush vset site_frontpage pacman/info

# Set timezone to Europe/Amsterdam
drush vset date_default_timezone 'Europe/Amsterdam' -y

# Set drupal to know of the reverse proxy used in docker
#TODO proxy ip dynamic
drush vset reverse_proxy 'TRUE'
php -r "print json_encode(array('172.20.0.2'));"  | drush vset --format=json reverse_proxy_addresses -

# Enable and make theme default
cd /var/www/html && drush vset theme_default fhml_um

apache2-foreground
