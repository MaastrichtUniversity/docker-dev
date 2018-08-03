FROM centos:7

RUN yum install -y \
    # extra repository to download extra packages
    epel-release

RUN yum install -y \
    # backwards compatibility for 'service'-command that is used by the iRODS-install script
    initscripts \
    sudo \
    wget \
    unixODBC \
#    super \
    fuse-libs \
    perl-JSON \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    lsof \
    nano \
    cifs-utils  \
    openssl \
    openssl-devel \
    libcurl-devel \
    curl \
    # packages required for building ruleset and microservices
    gcc-c++ \
    make \
    rpm-build
# Ubuntu 14.04 package manager contains a very old version of cmake.
# Install modern version with: (found on https://askubuntu.com/questions/952429/is-there-are-good-ppa-for-cmake-backports)
ENV CMAKE_VERSION 3.12
ENV CMAKE_LONG_VERSION 3.12.0
RUN cd /tmp && \
    wget https://cmake.org/files/v${CMAKE_VERSION}/cmake-${CMAKE_LONG_VERSION}-Linux-x86_64.sh && \
    sudo sh cmake-${CMAKE_LONG_VERSION}-Linux-x86_64.sh --prefix=/usr/local --exclude-subdir


# Setting locale (for gcc compiler), see https://github.com/CentOS/sig-cloud-instance-images/issues/71#issuecomment-266959225
RUN localedef -i en_US -f UTF-8 en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV IRODS_VERSION 4.2.3

# install iRODS
RUN rpm --import https://packages.irods.org/irods-signing-key.asc \
    && wget -qO - https://packages.irods.org/renci-irods.yum.repo | sudo tee /etc/yum.repos.d/renci-irods.yum.repo \
    && yum install -y \
    irods-server-${IRODS_VERSION} \
    irods-devel-${IRODS_VERSION} \
    # packages required for building microservices
    irods-externals-clang-runtime3.8-0 \
    irods-externals-clang3.8-0


# install Metalnx RMD
# Installation of rpm tries to start the rmd service, which causes D-Bus errors to appear. These can be safely ignored
# since we will start the rmd-service manually in bootstrap.sh
RUN wget https://bintray.com/metalnx/rpm/download_file?file_path=emc-metalnx-rmd-1.0-22.noarch.rpm -O /tmp/emc-metalnx-rmd.rpm \
    && rpm -Uvh /tmp/emc-metalnx-rmd.rpm

RUN mkdir /opt/irods

## Bug in cifs-utils package causes setcifsacl not to work without setting this symlink
## https://bugs.launchpad.net/ubuntu/+source/cifs-utils/+bug/1372120
#RUN mkdir /etc/cifs-utils && ln -s /usr/lib/x86_64-linux-gnu/cifs-utils/idmapwb.so /etc/cifs-utils/idmap-plugin
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

RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-5.2.0-x86_64.rpm -O /tmp/filebeat.rpm \
 && rpm -Uvh /tmp/filebeat.rpm

ADD filebeat.yml /etc/filebeat/filebeat.yml

###############################################################################


ENV DOCKERIZE_VERSION v0.2.0
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz -o dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# With iRODS 4.1.10, iRODS needs a force restart. Waiting for port 1248 is therefore not reliable. Wait for Metalnx RMD instead.
CMD dockerize -wait tcp://ires:8000 -timeout 200s /opt/irods/bootstrap.sh