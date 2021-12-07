FROM ubuntu:18.04

# Load build arguments from environment
ARG ENV_IRODS_VERSION
ARG ENV_IRODS_EXT_CLANG_VERSION
ARG ENV_IRODS_EXT_CLANG_RUNTIME_VERSION
ARG ENV_IRODS_RESC_PLUGIN_S3_VERSION
ARG ENV_DOCKERIZE_VERSION
ARG ENV_FILEBEAT_VERSION

# Use apt-get NL mirrors and install packages
RUN sed --in-place --regexp-extended "s/(\/\/)(archive\.ubuntu)/\1nl.\2/" /etc/apt/sources.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    wget \
    less \
    unixodbc \
    super \
    libfuse2 \
    libjson-perl \
    librabbitmq-dev \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    python-tz \
    sudo \
    lsof \
    fortune-mod \
    curl \
    joe \
    nano \
    uuid-dev \
    libssl-dev \
    build-essential \
    libxml2-dev \
    lsb-release \
    libcurl4-gnutls-dev \
    libs3-2 \
    libc++-dev \
    jq \
    # packages required for building ruleset and microservices {{
    libssl-dev \
    g++ \
    make \
    cmake \
    git \
    python-pip
    # }} end

ENV IRODS_VERSION ${ENV_IRODS_VERSION}

# install iRODS
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | sudo apt-key add - \
    && echo "deb [arch=amd64] https://packages.irods.org/apt/ xenial main" | sudo tee /etc/apt/sources.list.d/renci-irods.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    irods-server=${IRODS_VERSION} \
    irods-dev=${IRODS_VERSION} \
    irods-runtime=${IRODS_VERSION} \
    irods-icommands=${IRODS_VERSION} \
    # packages required for building microservices
    irods-externals-clang-runtime${ENV_IRODS_EXT_CLANG_RUNTIME_VERSION} \
    irods-externals-clang${ENV_IRODS_EXT_CLANG_VERSION} \
    # packages required for S3 storage plugin
    irods-resource-plugin-s3=${ENV_IRODS_RESC_PLUGIN_S3_VERSION} \
    # packages required for python rule engine
    irods-rule-engine-plugin-python=${IRODS_VERSION}

# install Metalnx RMD
ADD ./emc-metalnx-rmd-1.0-1.deb /tmp/emc-metalnx-rmd-1.0-1.deb
RUN dpkg -i /tmp/emc-metalnx-rmd-1.0-1.deb

# Filebeat
RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ENV_FILEBEAT_VERSION}-amd64.deb -O /tmp/filebeat.deb \
 && dpkg -i /tmp/filebeat.deb
ADD filebeat.yml /etc/filebeat/filebeat.yml
RUN chmod go-w /etc/filebeat/filebeat.yml


# Dockerize
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/${ENV_DOCKERIZE_VERSION}/dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz -o dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz

# Finalize
RUN mkdir /opt/irods

ADD ./setup_responses /etc/irods/setup_responses
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
ADD ./add_rule_engine.py /opt/irods/add_rule_engine.py
ADD ./add_env_var.py /opt/irods/add_env_var.py
ADD ./add_ssl_setting_at_setup.patch /opt/irods/add_ssl_setting_at_setup.patch

# SSL
ADD ./SSL /etc/irods/SSL

# Temporary fix needed with iRODS 4.2.6, after upgrading this shouldnt be necessary anymore
# https://github.com/agracio/electron-edge-js/issues/16
RUN ln -s /usr/include/locale.h /usr/include/xlocale.h

RUN chmod a+x /opt/irods/*

EXPOSE 1248 1247 8000
CMD dockerize -wait tcp://irods.dh.local:1247 -timeout 200s /opt/irods/bootstrap.sh
