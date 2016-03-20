#!/bin/bash

cd /var/www/html/sites/all/modules/pacman && composer update

cd /var/www/html/sites/all/modules/handsontable && bower install --allow-root

cd /var/www/html && drush site-install \
	--db-url=mysql://root:foobar@db:3306/pacman \
	--yes \
	--account-name=rit-admin \
	--account-pass=foobar \
	--site-name=pacman

cd /var/www/html && drush en \
	--yes \
	xml_forms \
	pacman \
	handsontable

apache2-foreground
