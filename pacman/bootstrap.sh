#!/bin/bash

cd /var/www/html

drush site-install \
	--db-url=mysql://root:foobar@db:3306/pacman \
	--yes \
	--account-name=rit-admin \
	--account-pass=foobar \
	--site-name=pacman

drush en \
	--yes \
	xml_forms

apache2-foreground
