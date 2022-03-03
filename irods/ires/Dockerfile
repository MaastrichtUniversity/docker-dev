# syntax=docker/dockerfile:1
FROM irods-base:ubuntu

# Load build arguements from environment
ARG ENV_DOCKERIZE_VERSION

# install packages for this iRES
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    cifs-utils \
    curl

# Overwrite the default setcifsacl with our own recompiled version
ADD ./patch/setcifsacl /usr/bin/setcifsacl
RUN chmod a+x /usr/bin/setcifsacl

# Dockerize install
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/${ENV_DOCKERIZE_VERSION}/dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz -o dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-${ENV_DOCKERIZE_VERSION}.tar.gz

# Add config
ADD ./config/irods/* /etc/irods/
ADD ./config/filebeat.yml /etc/filebeat/filebeat.yml
#RUN chmod go-w /etc/filebeat/filebeat.yml  # TODO: Is this needed?

# Add ires certs
ADD ./test-dev-ssl-certs/* /etc/irods/SSL/

# Add bootstrap scripts
ADD ./scripts/* /opt/irods/

EXPOSE 1248 1247 8000
CMD ["dockerize", "-wait", "tcp://irods.dh.local:1247", "-timeout", "200s", "/opt/irods/bootstrap.sh"]
