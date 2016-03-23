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
    lsof \
    make

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


RUN mkdir /opt/irods

ADD ./genresp.sh /opt/irods/genresp.sh
ADD ./setupdb.sh /opt/irods/setupdb.sh
ADD ./config.sh /opt/irods/config.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
RUN chmod a+x /opt/irods/*

EXPOSE 1248 1247

VOLUME [ "/rules", "/helpers" ]

ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
