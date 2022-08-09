# syntax=docker/dockerfile:1
ARG ENV_REGISTRY_HOST
ARG ENV_BRANCH
FROM ${ENV_REGISTRY_HOST}/docker-dev/${ENV_BRANCH}/irods-base:ubuntu

# install packages for this iRES
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    cifs-utils

# Overwrite the default setcifsacl with our own recompiled version
ADD ./patch/setcifsacl /usr/bin/setcifsacl
RUN chmod a+x /usr/bin/setcifsacl

# Add config
ADD ./config/irods/* /etc/irods/
ADD ./config/filebeat.yml /etc/filebeat/filebeat.yml
RUN chmod go-w /etc/filebeat/filebeat.yml

# Add ires certs
ADD ./test-dev-ssl-certs/* /etc/irods/SSL/

# Add bootstrap scripts
ADD ./scripts/* /opt/irods/

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s CMD su irods -c /opt/irods/check_health.sh

EXPOSE 1248 1247 8000
CMD ["/opt/irods/bootstrap.sh"]
