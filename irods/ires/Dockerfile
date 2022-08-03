# syntax=docker/dockerfile:1
ARG ENV_REGISTRY_HOST
ARG ENV_BRANCH
FROM ${ENV_REGISTRY_HOST}/docker-dev/${ENV_BRANCH}/irods-base:ubuntu

# Load build arguements from environment
ARG ENV_DOCKERIZE_VERSION

# install packages for this iRES
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    cifs-utils \
    python-pip \
    python3-distutils \
    software-properties-common

RUN add-apt-repository -y ppa:deadsnakes/ppa
RUN apt-get install -y python3.10 python3.10-distutils

# Overwrite the default setcifsacl with our own recompiled version
ADD ./patch/setcifsacl /usr/bin/setcifsacl
RUN chmod a+x /usr/bin/setcifsacl

# Dockerize install
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/${ENV_DOCKERIZE_VERSION}/dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz -o dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz

# Add config
ADD ./config/irods/* /etc/irods/
ADD ./config/filebeat.yml /etc/filebeat/filebeat.yml
RUN chmod go-w /etc/filebeat/filebeat.yml

# Add ires certs
ADD ./test-dev-ssl-certs/* /etc/irods/SSL/

# Conditionally trust the custom DataHub *Dev/Test-only* Certificate Authority (CA) for iRODS-SSL-connections
# Note: Python docker image is Debian-based. So, 'dash' as /bin/sh.
#       Strict POSIX-compliant.
RUN echo "Adding custom DataHub iRODS-CA-certificate to the CA-rootstore (FOR DEV & TEST ONLY!)..."
RUN cp /etc/irods/SSL/test_only_dev_irods_dh_ca_cert.pem /usr/local/share/ca-certificates/test_only_dev_irods_dh_ca_cert.crt ; \
update-ca-certificates ;

ADD ./patch/Add_failure_check.patch /var/lib/irods/Add_failure_check.patch

# Add bootstrap scripts
ADD ./scripts/* /opt/irods/

EXPOSE 1248 1247 8000
CMD ["dockerize", "-wait", "tcp://irods.dh.local:1247", "-timeout", "200s", "/opt/irods/bootstrap.sh"]
