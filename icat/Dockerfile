FROM ubuntu:18.04

# Load build arguments from environment
ARG ENV_POSTGRES_VERSION
ARG ENV_IRODS_VERSION
ARG ENV_IRODS_EXT_CLANG_VERSION
ARG ENV_IRODS_EXT_CLANG_RUNTIME_VERSION
ARG ENV_FILEBEAT_VERSION

# Use apt-get NL mirrors and install packages
RUN sed --in-place --regexp-extended "s/(\/\/)(archive\.ubuntu)/\1nl.\2/" /etc/apt/sources.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    wget \
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
    fortune-mod \
    nano \
    # packages required to parse keycloak/user.json
    jq \
    # packages required for building ruleset and microservices {{
    libssl-dev \
    libcurl4-openssl-dev \
    g++ \
    make \
    cmake \
    python-pip
    # }} end

# Make sure to use the same postgres version for client and irods-db server
RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo 'deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main' | sudo tee /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postgresql-client-${ENV_POSTGRES_VERSION} \
    odbc-postgresql

# install iRODS
ENV IRODS_VERSION ${ENV_IRODS_VERSION}
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | apt-key add - \
    && echo "deb [arch=amd64] https://packages.irods.org/apt/ xenial main" | sudo tee /etc/apt/sources.list.d/renci-irods.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    irods-server=${IRODS_VERSION} \
    irods-database-plugin-postgres=${IRODS_VERSION} \
    irods-dev=${IRODS_VERSION} \
    irods-runtime=${IRODS_VERSION} \
    irods-icommands=${IRODS_VERSION} \
    # packages required for building microservices
    irods-externals-clang-runtime${ENV_IRODS_EXT_CLANG_RUNTIME_VERSION} \
    irods-externals-clang${ENV_IRODS_EXT_CLANG_VERSION} \
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

# Finalize
RUN mkdir /opt/irods
ADD ./setup_responses /etc/irods/setup_responses
ADD ./setupdb.sh /opt/irods/setupdb.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
ADD ./add_rule_engine.py /opt/irods/add_rule_engine.py
ADD ./add_env_var.py /opt/irods/add_env_var.py

# Temporary fix for the CAT_STATEMENT_TABLE_FULL error in iRODS 4.2.6
# https://github.com/irods/irods/issues/4438
# https://github.com/irods/irods_rule_engine_plugin_python/commit/9f957078569c75a4f539c297138a0bb0d3e1824c 
ADD ./genquery.py /etc/irods/genquery.py

# Temporary fix needed with iRODS 4.2.6, after upgrading this shouldnt be necessary anymore
# https://github.com/agracio/electron-edge-js/issues/16
RUN ln -s /usr/include/locale.h /usr/include/xlocale.h

RUN chmod a+x /opt/irods/*

EXPOSE 1248 1247 8000
VOLUME [ "/rules", "/helpers", "/microservices" ]
ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
