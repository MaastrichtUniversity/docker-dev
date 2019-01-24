FROM ubuntu:14.04

ARG ENV_IRODS_VERSION

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    wget \
    libfuse2 \
    libcurl4-gnutls-dev

# install iRODS icommands
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | sudo apt-key add - \
    && echo "deb [arch=amd64] https://packages.irods.org/apt/ trusty main" | sudo tee /etc/apt/sources.list.d/renci-irods.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    irods-icommands=${ENV_IRODS_VERSION}

RUN useradd -ms /bin/bash irods
WORKDIR /home/irods
RUN mkdir /home/irods/.irods

ADD ./icommand.sh /home/irods/icommand.sh

RUN chown -R irods:irods /home/irods

USER irods
ENTRYPOINT [ "/home/irods/icommand.sh" ]
