FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    wget \
    unixodbc \
    super \
    libfuse2 \
    libjson-perl \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    sudo \
    lsof \
    cifs-utils  \
    curl \
    nano \
    # packages required for building ruleset and microservices {{
    libssl-dev \
    libcurl4-openssl-dev \
<<<<<<< HEAD
    g++ \
    make
    # }} end
# Ubuntu 14.04 package manager contains a very old version of cmake.
# Install modern version with: (found on https://askubuntu.com/questions/952429/is-there-are-good-ppa-for-cmake-backports)
ENV CMAKE_VERSION 3.12
ENV CMAKE_LONG_VERSION 3.12.0
RUN cd /tmp && \
    wget https://cmake.org/files/v${CMAKE_VERSION}/cmake-${CMAKE_LONG_VERSION}-Linux-x86_64.sh && \
    sudo sh cmake-${CMAKE_LONG_VERSION}-Linux-x86_64.sh --prefix=/usr/local --exclude-subdir

ENV IRODS_VERSION 4.2.3
=======
    curl \
    librabbitmq-dev \
    nano


RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV IRODS_VERSION 4.1.12
>>>>>>> master

# install iRODS
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | sudo apt-key add - \
    && echo "deb [arch=amd64] https://packages.irods.org/apt/ trusty main" | sudo tee /etc/apt/sources.list.d/renci-irods.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    irods-server=${IRODS_VERSION} \
    irods-dev=${IRODS_VERSION} \
    # packages required for building microservices
    irods-externals-clang-runtime3.8-0 \
    irods-externals-clang3.8-0

# install Metalnx RMD
ADD ./emc-metalnx-rmd-1.0-1.deb /tmp/emc-metalnx-rmd-1.0-1.deb
RUN dpkg -i /tmp/emc-metalnx-rmd-1.0-1.deb

RUN mkdir /opt/irods

# Bug in cifs-utils package causes setcifsacl not to work without setting this symlink
# https://bugs.launchpad.net/ubuntu/+source/cifs-utils/+bug/1372120
RUN mkdir /etc/cifs-utils && ln -s /usr/lib/x86_64-linux-gnu/cifs-utils/idmapwb.so /etc/cifs-utils/idmap-plugin

ADD ./setup_responses /etc/irods/setup_responses
ADD ./config.sh /opt/irods/config.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
ADD ./add_env_var.py /opt/irods/add_env_var.py
RUN chmod a+x /opt/irods/*

# Overwrite the default setcifsacl with our own recompiled version
ADD ./setcifsacl /usr/bin/setcifsacl
RUN chmod a+x /usr/bin/setcifsacl

EXPOSE 1248 1247 8000

###############################################################################
#                                INSTALLATION FILEBEAT
###############################################################################

RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-5.2.0-amd64.deb -O /tmp/filebeat.deb \
 && dpkg -i /tmp/filebeat.deb

ADD filebeat.yml /etc/filebeat/filebeat.yml

###############################################################################



ENV DOCKERIZE_VERSION v0.2.0
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz -o dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz
# With iRODS 4.1.10, iRODS needs a force restart. Waiting for port 1248 is therefore not reliable. Wait for Metalnx RMD instead.
CMD dockerize -wait tcp://irods:8000 -timeout 200s /opt/irods/bootstrap.sh