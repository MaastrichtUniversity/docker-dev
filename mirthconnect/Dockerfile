# Adapted from https://github.com/brandonstevens/mirth-connect-docker
FROM java

ENV MIRTH_CONNECT_VERSION 3.4.1.8057.b139

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    vim \
    postgresql-client

### Preparations for git clone from bitbucket. Cloning the repo can only be done during runtime --> see docker-entrypoint.sh
# Copy over private key, and set permissions
ADD id_rsa /root/.ssh/id_rsa
RUN chmod 400 /root/.ssh/id_rsa
# Create known_hosts
RUN touch /root/.ssh/known_hosts


# Mirth Connect is run with user `connect`, uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN useradd -u 1000 mirth

# grab gosu for easy step-down from root
RUN gpg --keyserver pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
	&& wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/1.2/gosu-$(dpkg --print-architecture)" \
	&& wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/1.2/gosu-$(dpkg --print-architecture).asc" \
	&& gpg --verify /usr/local/bin/gosu.asc \
	&& rm /usr/local/bin/gosu.asc \
	&& chmod +x /usr/local/bin/gosu

VOLUME /opt/mirth-connect/appdata

RUN \
  cd /tmp && \
  wget http://downloads.mirthcorp.com/connect/$MIRTH_CONNECT_VERSION/mirthconnect-$MIRTH_CONNECT_VERSION-unix.tar.gz && \
  tar xvzf mirthconnect-$MIRTH_CONNECT_VERSION-unix.tar.gz && \
  rm -f mirthconnect-$MIRTH_CONNECT_VERSION-unix.tar.gz && \
  mv Mirth\ Connect/* /opt/mirth-connect/ && \
  chown -R mirth /opt/mirth-connect

WORKDIR /opt/mirth-connect

EXPOSE 9090 9443

ADD ./mirth.properties /opt/mirth-connect/conf/mirth.properties
ADD ./mirth-cli-config.properties /opt/mirth-connect/conf/mirth-cli-config.properties
ADD ./docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]

CMD ["java", "-jar", "mirth-server-launcher.jar"]