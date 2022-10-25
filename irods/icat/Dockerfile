# syntax=docker/dockerfile:1
ARG ENV_REGISTRY_HOST
ARG ENV_BRANCH
FROM ${ENV_REGISTRY_HOST}/docker-dev/${ENV_BRANCH}/irods-base:ubuntu

# Load build arguments from environment
ARG ENV_POSTGRES_CLIENT_VERSION
ARG ENV_POSTGRES_VERSION
ARG ENV_IRODS_VERSION

# Make sure to use the same postgres version for client and irods-db server
RUN wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo 'deb http://apt.postgresql.org/pub/repos/apt/ bionic-pgdg main' | sudo tee /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    postgresql-client-${ENV_POSTGRES_CLIENT_VERSION} \
    odbc-postgresql \
    irods-database-plugin-postgres=${ENV_IRODS_VERSION}

# Temporary fix for the CAT_STATEMENT_TABLE_FULL error in iRODS 4.2.6
# https://github.com/irods/irods/issues/4438
# https://github.com/irods/irods_rule_engine_plugin_python/commit/9f957078569c75a4f539c297138a0bb0d3e1824c
ADD ./patch/genquery.py /etc/irods/genquery.py

# Add DMFS fakers (SURFsara tape)
ADD ./DMFS/* /var/lib/irods/msiExecCmd_bin/
RUN chmod 755 /var/lib/irods/msiExecCmd_bin/dm*

# files containing configuration to be parsed during install
ADD ./config/irods/* /etc/irods/
ADD ./config/filebeat.yml /etc/filebeat/filebeat.yml
RUN chmod go-w /etc/filebeat/filebeat.yml

# Add icat certs
ADD ./test-dev-ssl-certs/* /etc/irods/SSL/

# bootstrap scripts to build our development iCAT
ADD ./scripts/* /opt/irods/

EXPOSE 1248 1247 8000
VOLUME [ "/rules", "/helpers", "/microservices" ]
# will install iRODS on start of container
ENTRYPOINT [ "/opt/irods/bootstrap.sh" ]
