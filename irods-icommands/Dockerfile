FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget \
    libfuse2 \
    libcurl4-gnutls-dev

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV IRODS_VERSION 4.1.10

# install iRODS icommands

RUN wget ftp://ftp.renci.org/pub/irods/releases/${IRODS_VERSION}/ubuntu14/irods-icommands-${IRODS_VERSION}-ubuntu14-x86_64.deb -O /tmp/irods-icat.deb \
    && dpkg -i /tmp/irods-icat.deb

RUN useradd -ms /bin/bash irods
WORKDIR /home/irods
RUN mkdir /home/irods/.irods

ADD ./icommand.sh /home/irods/icommand.sh

RUN chown -R irods:irods /home/irods

USER irods
ENTRYPOINT [ "/home/irods/icommand.sh" ]
