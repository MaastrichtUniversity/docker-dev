FROM drupal:7.43-apache

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

ENV ISLANDORA_VERSION 1.6

RUN curl -fSL "https://github.com/islandora/islandora_xml_forms/archive/7.x-${ISLANDORA_VERSION}.zip" -o islandora_xml_forms.zip \
	&& unzip islandora_xml_forms.zip \
	&& rm islandora_xml_forms.zip \
	&& chown -R www-data:www-data .

RUN curl -fSL "https://github.com/islandora/php_lib/archive/7.x-${ISLANDORA_VERSION}.zip" -o php_lib.zip \
	&& unzip php_lib.zip \
	&& rm php_lib.zip \
	&& chown -R www-data:www-data .

RUN curl -fSL "https://github.com/islandora/objective_forms/archive/7.x-${ISLANDORA_VERSION}.zip" -o objective_forms.zip \
	&& unzip objective_forms.zip \
	&& rm objective_forms.zip \
	&& chown -R www-data:www-data .

RUN curl -fSL https://getcomposer.org/download/1.0.0-beta1/composer.phar -o /usr/bin/composer \
	&& chmod +x /usr/bin/composer

RUN npm install -g bower

RUN curl -fSL http://files.drush.org/drush.phar -o /usr/bin/drush \
	&& chmod +x /usr/bin/drush

VOLUME [ "/var/www/html/sites/all/modules/pacman", "/var/www/html/sites/all/modules/handsontable", "/var/www/html/sites/all/modules/rit_forms" ,"/var/www/html/sites/all/themes/fhml_um_theme_demo","/var/www/html/sites/all/modules/cloudbrowser_module" ]

ADD bootstrap.sh /var/www/html/
RUN chmod +x /var/www/html/bootstrap.sh

CMD /var/www/html/bootstrap.sh
