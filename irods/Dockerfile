FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
    cifs-utils \
    software-properties-common \
    python-software-properties

RUN echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | /usr/bin/debconf-set-selections
RUN apt-add-repository ppa:webupd8team/java && apt-get update && apt-get install oracle-java8-installer -y

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV IRODS_VERSION 4.1.8

# install iRODS

RUN wget ftp://ftp.renci.org/pub/irods/releases/${IRODS_VERSION}/ubuntu14/irods-icat-${IRODS_VERSION}-ubuntu14-x86_64.deb -O /tmp/irods-icat.deb \
    && dpkg -i /tmp/irods-icat.deb

RUN wget ftp://ftp.renci.org/pub/irods/releases/${IRODS_VERSION}/ubuntu14/irods-database-plugin-postgres-1.8-ubuntu14-x86_64.deb -O /tmp/irods-dbplugin.deb \
    && dpkg -i /tmp/irods-dbplugin.deb


RUN mkdir /opt/irods && mkdir /mnt/ingestZone

# Bug in cifs-utils package causes setcifsacl not to work without setting this symlink
# https://bugs.launchpad.net/ubuntu/+source/cifs-utils/+bug/1372120
RUN mkdir /etc/cifs-utils && ln -s /usr/lib/x86_64-linux-gnu/cifs-utils/idmapwb.so /etc/cifs-utils/idmap-plugin

ADD ./genresp.sh /opt/irods/genresp.sh
ADD ./setupdb.sh /opt/irods/setupdb.sh
ADD ./config.sh /opt/irods/config.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
RUN chmod a+x /opt/irods/*

# Install iRODS-REST
RUN wget -P /tmp/ http://apache.mirror1.spango.com/tomcat/tomcat-8/v8.0.33/bin/apache-tomcat-8.0.33.tar.gz
RUN wget -P /tmp/ https://code.renci.org/gf/download/frsrelease/243/2742/irods-rest.war
RUN tar xvf /tmp/apache-tomcat-8.0.33.tar.gz -C /tmp/ && mv /tmp/apache-tomcat-8.0.33/ /var/lib/tomcat8
RUN mv /tmp/irods-rest.war /var/lib/tomcat8/webapps/ && mkdir /etc/irods-ext
ADD ./irods-rest.properties /etc/irods-ext/irods-rest.properties

EXPOSE 1248 1247

VOLUME [ "/rules", "/helpers" ]

ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
