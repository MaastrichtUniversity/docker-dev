FROM drupal:7.50-apache

RUN apt-get update && apt-get install -y \
	unzip \
	libxslt-dev \
	mysql-client \
	git \
	nodejs \
	npm

RUN docker-php-ext-install -j$(nproc) xsl

RUN pecl install xdebug \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.remote_host=172.17.0.1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

WORKDIR /var/www/html/sites/all/modules

RUN ln -s /usr/bin/nodejs /usr/bin/node

ENV DOCKERIZE_VERSION v0.2.0
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz -o dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

ENV ISLANDORA_VERSION 1.6

RUN curl -fSL "https://github.com/islandora/islandora_xml_forms/archive/7.x-${ISLANDORA_VERSION}.zip" -o islandora_xml_forms.zip \
	&& unzip islandora_xml_forms.zip \
	&& rm islandora_xml_forms.zip \
	&& chown -R www-data:www-data .

# This is a workarround for Drupal 7.50 and Islandora < 1.8.
# Required untill this PR has been included in Islandora 1.8:
# https://github.com/Islandora/islandora_xml_forms/pull/229
RUN sed -i "s|schema  _api|xml_schema_api|" /var/www/html/sites/all/modules/islandora_xml_forms-7.x-${ISLANDORA_VERSION}/api/schema/Extension.inc

RUN curl -fSL "https://github.com/islandora/php_lib/archive/7.x-${ISLANDORA_VERSION}.zip" -o php_lib.zip \
	&& unzip php_lib.zip \
	&& rm php_lib.zip \
	&& chown -R www-data:www-data .

RUN curl -fSL "https://github.com/islandora/objective_forms/archive/7.x-${ISLANDORA_VERSION}.zip" -o objective_forms.zip \
	&& unzip objective_forms.zip \
	&& rm objective_forms.zip \
	&& chown -R www-data:www-data .

RUN curl -fSL "https://github.com/Michigan-State-University/islandora_xml_form_builder_states/archive/master.zip" -o islandora_xml_form_builder_states.zip \
	&& unzip islandora_xml_form_builder_states.zip \
	&& rm islandora_xml_form_builder_states.zip \
	&& chown -R www-data:www-data .

RUN curl -fSL https://getcomposer.org/download/1.0.0-beta1/composer.phar -o /usr/bin/composer \
	&& chmod +x /usr/bin/composer

RUN npm install -g bower

RUN curl -fSL http://files.drush.org/drush.phar -o /usr/bin/drush \
	&& chmod +x /usr/bin/drush

# Get jquery update for Drupal
RUN cd /var/www/html \
    && drush dl jquery_update

VOLUME [ "/var/www/html/sites/all/modules/pacman", "/var/www/html/sites/all/modules/handsontable", "/var/www/html/sites/all/modules/rit_forms" ,"/var/www/html/sites/all/themes/fhml_um_theme_demo","/var/www/html/sites/all/modules/cloudbrowser_module", "/var/www/html/sites/all/modules/islandora_ontology_autocomplete", "/var/www/html/sites/all/modules/rit_faker" ]

WORKDIR /var/www/html

ADD bootstrap.sh /var/www/html/
RUN chmod +x /var/www/html/bootstrap.sh

CMD dockerize -stdout /var/log/apache2/access.log -stderr /var/log/apache2/error.log -wait tcp://db:3306 -wait tcp://irods:1248 -timeout 30s /var/www/html/bootstrap.sh
