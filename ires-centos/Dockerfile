FROM centos:7

# Load build arguments from environment
ARG ENV_IRODS_VERSION
ARG ENV_IRODS_EXT_CLANG_VERSION
ARG ENV_IRODS_EXT_CLANG_RUNTIME_VERSION
ARG ENV_DOCKERIZE_VERSION
ARG ENV_FILEBEAT_VERSION

RUN yum install -y \
    # extra repository to download extra packages
    epel-release \
    ca-certificates

RUN yum install -y \
    # backwards compatibility for 'service'-command that is used by the iRODS-install script
    initscripts \
    sudo \
    wget \
    unixODBC \
    fuse-libs \
    librabbitmq-devel \
    perl-JSON \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    lsof \
    fortune-mod \
    nano \
    cifs-utils  \
    openssl \
    curl \
    jq \
    # packages required for building ruleset and microservices {{
    openssl-devel \
    libcurl-devel \
    gcc-c++ \
    make \
    rpm-build \
    cmake3 \
    python-pip
    # }} end


ENV IRODS_VERSION ${ENV_IRODS_VERSION}

# install iRODS
RUN rpm --import https://packages.irods.org/irods-signing-key.asc \
    && wget -qO - https://packages.irods.org/renci-irods.yum.repo | sudo tee /etc/yum.repos.d/renci-irods.yum.repo \
    && yum install -y \
    irods-server-${IRODS_VERSION} \
    irods-devel-${IRODS_VERSION} \
    # packages required for building microservices
    irods-externals-clang-runtime${ENV_IRODS_EXT_CLANG_RUNTIME_VERSION} \
    irods-externals-clang${ENV_IRODS_EXT_CLANG_VERSION} \
    # packages required for python rule engine
    irods-rule-engine-plugin-python-${IRODS_VERSION}

# install Metalnx RMD
# Installation of rpm tries to start the rmd service, which causes D-Bus errors to appear. These can be safely ignored
# since we will start the rmd-service manually in bootstrap.sh
ADD ./emc-metalnx-rmd-1.0-22.noarch.rpm /tmp/emc-metalnx-rmd-1.0-22.noarch.rpm
RUN rpm -Uvh /tmp/emc-metalnx-rmd-1.0-22.noarch.rpm

# Overwrite the default setcifsacl with our own recompiled version
ADD ./setcifsacl /usr/bin/setcifsacl
RUN chmod a+x /usr/bin/setcifsacl

# Filebeat
RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ENV_FILEBEAT_VERSION}-x86_64.rpm -O /tmp/filebeat.rpm \
 && rpm -Uvh /tmp/filebeat.rpm
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
RUN chmod a+x /opt/irods/*

# SSL
ADD ./SSL /etc/irods/SSL

CMD dockerize -wait tcp://irods.dh.local:1247 -timeout 200s /opt/irods/bootstrap.sh
EXPOSE 1248 1247 8000
