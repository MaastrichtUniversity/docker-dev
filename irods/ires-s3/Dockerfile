# syntax=docker/dockerfile:1
FROM irods-base:ubuntu

# Load build arguements from environment
ARG ENV_DOCKERIZE_VERSION
ARG ENV_IRODS_RESC_PLUGIN_S3_VERSION

# Install packages needed for iRES-S3
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential \
    git \
    joe \
    less \
    libc++-dev \
    libcurl4-gnutls-dev \
    libs3-2 \
    libxml2-dev \
    lsb-release \
    python-tz \
    uuid-dev \
    irods-resource-plugin-s3=${ENV_IRODS_RESC_PLUGIN_S3_VERSION}

# Dockerize
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/${ENV_DOCKERIZE_VERSION}/dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz -o dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz

# Add bootstrap scripts
ADD ./scripts/* /opt/irods/

# Add config
ADD ./config/irods/* /etc/irods/
ADD ./config/filebeat.yml /etc/filebeat/filebeat.yml
#RUN chmod go-w /etc/filebeat/filebeat.yml  # TODO: Is this needed?

# Add ires-s3 certs
ADD ./test-dev-ssl-certs/* /etc/irods/SSL/

EXPOSE 1248 1247 8000
CMD ["dockerize", "-wait", "tcp://irods.dh.local:1247", "-timeout", "200s", "/opt/irods/bootstrap.sh"]
