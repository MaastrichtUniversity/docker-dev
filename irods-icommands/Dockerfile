FROM ubuntu:18.04

ARG ENV_IRODS_VERSION

# Use apt-get NL mirrors and install packages
RUN sed --in-place --regexp-extended "s/(\/\/)(archive\.ubuntu)/\1nl.\2/" /etc/apt/sources.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apt-transport-https \
    gnupg \
    wget \
    libxml2

# install iRODS icommands
RUN wget -qO - https://packages.irods.org/irods-signing-key.asc | apt-key add - \
    && echo "deb [arch=amd64] https://packages.irods.org/apt/ xenial main" | tee /etc/apt/sources.list.d/renci-irods.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    irods-icommands=${ENV_IRODS_VERSION} \
    irods-runtime=${ENV_IRODS_VERSION}

RUN useradd -ms /bin/bash irods
WORKDIR /home/irods
RUN mkdir /home/irods/.irods

ADD ./icommand.sh /home/irods/icommand.sh

RUN chown -R irods:irods /home/irods

# Trust the custom DataHub Certificate Authority (CA) for iRODS-SSL-connections
ADD test_only_dev_irods_dh_ca_cert.pem /tmp/test_only_dev_irods_dh_ca_cert.pem
RUN echo "Adding custom DataHub iRODS-CA-certificate to the CA-rootstore (FOR DEV & TEST ONLY!)..." \
    && cp /tmp/test_only_dev_irods_dh_ca_cert.pem /usr/local/share/ca-certificates/test_only_dev_irods_dh_ca_cert.crt \
    # Note that update-ca-certificates on Ubuntu wants the .crt extension (does not accept .pem)
    && update-ca-certificates

USER irods
ENTRYPOINT [ "/home/irods/icommand.sh" ]
