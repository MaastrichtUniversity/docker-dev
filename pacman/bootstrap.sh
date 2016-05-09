#!/bin/bash

until mysql -h db -uroot -pfoobar &> /dev/null; do
  >&2 echo "MySQL is unavailable - sleeping"
  sleep 1
done

cd /var/www/html/sites/all/modules/pacman && composer update

cd /var/www/html/sites/all/modules/handsontable && bower install --allow-root

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
	cloudbrowser \
	fhml_um \
	islandora_xml_form_builder_states

cd /var/www/html && drush add-rit-forms

cd /var/www/html && drush user-create p.vanschayck --password="foobar"
cd /var/www/html && drush user-create m.coonen --password="foobar"
cd /var/www/html && drush user-create d.theunissen --password="foobar"
cd /var/www/html && drush user-create p.suppers --password="foobar"

# Set homepage to pacman/info
cd /var/www/html && drush vset site_frontpage pacman/info

# Enable and make theme default
cd /var/www/html && drush vset theme_default fhml_um


apache2-foreground
