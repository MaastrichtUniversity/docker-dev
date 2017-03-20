FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    wget \
    unixodbc \
    super \
    odbc-postgresql \
    postgresql-client \
    libfuse2 \
    libjson-perl \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    lsof \
    make \
    g++ \
    libssl-dev \
    libcurl4-openssl-dev \
    fortune-mod


RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# install iRODS
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | sudo apt-key add - \
    && echo "deb [arch=amd64] https://packages.irods.org/apt/ trusty main" | sudo tee /etc/apt/sources.list.d/renci-irods.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    irods-server \
    irods-database-plugin-postgres \
    irods-dev

# install Metalnx RMD
ADD ./emc-metalnx-rmd-1.0-1.deb /tmp/emc-metalnx-rmd-1.0-1.deb
RUN dpkg -i /tmp/emc-metalnx-rmd-1.0-1.deb

RUN mkdir /opt/irods

ADD ./setup_responses /opt/irods/setup_responses
ADD ./setupdb.sh /opt/irods/setupdb.sh
ADD ./config.sh /opt/irods/config.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
ADD ./add_env_var.py /opt/irods/add_env_var.py
RUN chmod a+x /opt/irods/*

EXPOSE 1248 1247 8000

###############################################################################
#                                INSTALLATION FILEBEAT
###############################################################################

RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-5.2.0-amd64.deb -O /tmp/filebeat.deb \
 && dpkg -i /tmp/filebeat.deb

ADD filebeat.yml /etc/filebeat/filebeat.yml

###############################################################################

VOLUME [ "/rules", "/helpers", "/microservices" ]

ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
