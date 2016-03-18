FROM drupal:7.43-apache

RUN apt-get update && apt-get install -y \
	unzip \
	libxslt-dev \
	mysql-client

RUN docker-php-ext-install -j$(nproc) xsl

WORKDIR /var/www/html/sites/all/modules
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

RUN curl -fSL http://files.drush.org/drush.phar -o /usr/bin/drush \
	&& chmod +x /usr/bin/drush

ADD bootstrap.sh /var/www/html/

CMD /var/www/html/bootstrap.sh
