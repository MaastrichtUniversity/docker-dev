# Stay at PHP 5.6 for now
# TODO: Remember to update to latest xdebug version somewhat below if we ever upgrade to a recent PHP version.
FROM php:5.6-apache-jessie

RUN a2enmod rewrite

# install the PHP extensions we need
RUN apt-get update && apt-get install -y libpng12-dev libjpeg-dev libpq-dev \
    && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
    && docker-php-ext-install gd mbstring pdo pdo_mysql pdo_pgsql zip

WORKDIR /var/www/html

# https://www.drupal.org/node/3060/release
ENV DRUPAL_VERSION 7.50
ENV DRUPAL_MD5 f23905b0248d76f0fc8316692cd64753

RUN curl -fSL "http://ftp.drupal.org/files/projects/drupal-${DRUPAL_VERSION}.tar.gz" -o drupal.tar.gz \
    && echo "${DRUPAL_MD5} *drupal.tar.gz" | md5sum -c - \
    && tar -xz --strip-components=1 -f drupal.tar.gz \
    && rm drupal.tar.gz \
    && chown -R www-data:www-data sites

## The part above could be restructured to its own Drupal-php56 Dockerfile, but we best have an image repository before we do that
# New version of node required for yarn
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash -

RUN apt-get update && apt-get install -y \
    unzip \
    libxslt-dev \
    mysql-client \
    git \
    nodejs \
    nano

RUN docker-php-ext-install -j$(nproc) xsl

# Freeze xdebug version to 2.5.5 because 2.6.0 requires PHP 7 or higher 
# See changelog at https://pecl.php.net/package-changelog.php?package=xdebug&release=2.6.0
RUN pecl install xdebug-2.5.5 \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.remote_host=172.17.0.1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

WORKDIR /var/www/html/sites/all/modules

ENV DOCKERIZE_VERSION v0.2.0
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz -o dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

ENV ISLANDORA_VERSION 1.8

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

RUN curl -fSL "https://github.com/Michigan-State-University/islandora_xml_form_builder_states/archive/master.zip" -o islandora_xml_form_builder_states.zip \
    && unzip islandora_xml_form_builder_states.zip \
    && rm islandora_xml_form_builder_states.zip \
    && chown -R www-data:www-data .

RUN curl -fSL https://getcomposer.org/download/1.0.0-beta1/composer.phar -o /usr/bin/composer \
    && chmod +x /usr/bin/composer

RUN npm install -g yarn

RUN curl -fSL https://github.com/drush-ops/drush/releases/download/8.1.16/drush.phar -o /usr/bin/drush \
    && chmod +x /usr/bin/drush

# Get jquery update for Drupal
RUN cd /var/www/html \
    && drush dl jquery_update

ADD bootstrap.sh /var/www/html/
RUN chmod +x /var/www/html/bootstrap.sh


CMD dockerize -wait tcp://db:3306 -wait tcp://irods:1248 -timeout 80s /var/www/html/bootstrap.sh
