# syntax=docker/dockerfile:1
ARG ENV_REGISTRY_HOST
ARG ENV_BRANCH
FROM ${ENV_REGISTRY_HOST}/docker-dev/${ENV_BRANCH}/irods-base:centos

# Load build arguments from environment
ARG ENV_DOCKERIZE_VERSION

# Install redis-server
RUN yum install -y redis

# Install python dev dependencies
RUN yum install gcc openssl-devel bzip2-devel libffi-devel -y

# Install python 3.9
RUN cd /tmp/ && wget https://www.python.org/ftp/python/3.9.13/Python-3.9.13.tgz
RUN cd /tmp/ && tar -xzf Python-3.9.13.tgz
RUN cd /tmp/Python-3.9.13/ && ./configure --enable-optimizations
RUN cd /tmp/Python-3.9.13/ && make altinstall

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

# Add bootstrap scripts
ADD ./scripts/* /opt/irods/

EXPOSE 1248 1247 8000
# Note: centos image uses 'bash' for /bin/sh. Ubuntu uses 'dash'.
# When the CMD instruction is in shell form (without [" ",...]), docker will do
# '/bin/sh -c "dockerize -wait ..."'. The behaviour in bash is different from
# dash. My guess is, in bash if running as PID 1 (parent PID 0), it will behave
# as an exec and just let that process take control (PID 1). In dash, this is
# not the case and it will run as a child of shell (dash). This is incovenient
# because signals sent to PID 1 (dash), are not forwarded to dockerize. Which
# would make things like `docker-compose down` slow.
# Nevertheless, we leave this CMD in exec form for consistency.
CMD ["dockerize", "-wait", "tcp://irods.dh.local:1247", "-timeout", "200s", "/opt/irods/bootstrap.sh"]
