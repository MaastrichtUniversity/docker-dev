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
    cifs-utils 


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
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
RUN chmod a+x /opt/irods/*

EXPOSE 1248 1247

VOLUME [ "/rules", "/helpers" ]

ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
