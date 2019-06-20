FROM ubuntu:16.04

# Load build arguments from environment
ARG ENV_IRODS_VERSION
ARG ENV_IRODS_EXT_CLANG_VERSION
ARG ENV_IRODS_EXT_CLANG_RUNTIME_VERSION
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
    sudo \
    lsof \
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
    # packages required for building ruleset and microservices {{
    libssl-dev \
    g++ \
    make \
    cmake \
    git
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
    irods-externals-libs3a30e55e8-0

# install Metalnx RMD
ADD ./emc-metalnx-rmd-1.0-1.deb /tmp/emc-metalnx-rmd-1.0-1.deb
RUN dpkg -i /tmp/emc-metalnx-rmd-1.0-1.deb

RUN mkdir /opt/irods

ADD ./setup_responses /etc/irods/setup_responses
ADD ./config.sh /opt/irods/config.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
ADD ./add_env_var.py /opt/irods/add_env_var.py
RUN chmod a+x /opt/irods/*

ADD ./irods-resource-plugin-s3_2.5.0~xenial_amd64.deb /tmp/irods-resource-plugin-s3_2.5.0~xenial_amd64.deb


EXPOSE 1248 1247 8000

###############################################################################
#                                INSTALLATION FILEBEAT
###############################################################################

RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ENV_FILEBEAT_VERSION}-amd64.deb -O /tmp/filebeat.deb \
 && dpkg -i /tmp/filebeat.deb

ADD filebeat.yml /etc/filebeat/filebeat.yml

###############################################################################

RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/${ENV_DOCKERIZE_VERSION}/dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz -o dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz
# With iRODS 4.1.10, iRODS needs a force restart. Waiting for port 1248 is therefore not reliable. Wait for Metalnx RMD instead.
CMD dockerize -wait tcp://ires-s3-1:1247 -timeout 200s /opt/irods/bootstrap.sh
