FROM php:7.1-apache-stretch

# Load build arguments from environment
ARG ENV_XDEBUG_VERSION
ARG ENV_DRUPAL_VERSION
ARG ENV_DRUPAL_VERSION_MD5
ARG ENV_ISLANDORA_VERSION
ARG ENV_DOCKERIZE_VERSION
ARG ENV_FILEBEAT_VERSION

RUN apt-get update && apt-get install -y \
        unzip \
        libxslt-dev \
        mysql-client \
        git \
        nano \
        libjpeg-dev \
        libpq-dev \
        libpng-dev \
        libzip-dev \
        gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# PHP xsl extension
RUN docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr \
    && docker-php-ext-install -j$(nproc) \
        xsl \
        gd \
        mbstring \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        zip

# PHP xdebug extension
RUN pecl install xdebug-${ENV_XDEBUG_VERSION} \
    && docker-php-ext-enable xdebug \
    && echo "xdebug.remote_enable=on" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.remote_autostart=off" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini \
    && echo "xdebug.remote_host=172.17.0.1" >> /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Enable mod_rewrite
RUN a2enmod rewrite

# New version of node required for yarn
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get install -y nodejs

# https://www.drupal.org/node/3060/release
ENV DRUPAL_VERSION ${ENV_DRUPAL_VERSION}
ENV DRUPAL_MD5 ${ENV_DRUPAL_VERSION_MD5}

RUN cd /var/www/html \
    && curl -fSL "http://ftp.drupal.org/files/projects/drupal-${DRUPAL_VERSION}.tar.gz" -o drupal.tar.gz \
    && echo "${DRUPAL_MD5} *drupal.tar.gz" | md5sum -c - \
    && tar -xz --strip-components=1 -f drupal.tar.gz \
    && rm drupal.tar.gz \
    && chown -R www-data:www-data sites

RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/${ENV_DOCKERIZE_VERSION}/dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz -o dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz

WORKDIR /var/www/html/sites/all/modules
ENV ISLANDORA_VERSION ${ENV_ISLANDORA_VERSION}

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

RUN curl -fSL https://getcomposer.org/download/1.7.2/composer.phar -o /usr/bin/composer \
    && chmod +x /usr/bin/composer

RUN npm install -g yarn

RUN curl -fSL https://github.com/drush-ops/drush/releases/download/8.1.17/drush.phar -o /usr/bin/drush \
    && chmod +x /usr/bin/drush

# Get jquery update for Drupal
RUN cd /var/www/html \
    && drush dl --default-major=7 jquery_update

ADD bootstrap.sh /var/www/html/
RUN chmod +x /var/www/html/bootstrap.sh

CMD dockerize -wait tcp://db:3306 -wait tcp://irods:1248 -timeout 80s /var/www/html/bootstrap.sh
