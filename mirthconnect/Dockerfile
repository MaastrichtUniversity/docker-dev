# Adapted from https://github.com/brandonstevens/mirth-connect-docker
FROM java

ENV MIRTH_CONNECT_VERSION 3.4.1.8057.b139

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    vim \
    postgresql-client \
    netcat

# Mirth Connect is run with user 'mirth', uid = 1000
# If you bind mount a volume from the host or a data container,
# ensure you use the same uid
RUN useradd -u 1000 mirth

RUN mkdir /opt/mirth-connect

RUN \
  cd /tmp && \
  wget http://downloads.mirthcorp.com/connect/$MIRTH_CONNECT_VERSION/mirthconnect-$MIRTH_CONNECT_VERSION-unix.tar.gz && \
  tar xvzf mirthconnect-$MIRTH_CONNECT_VERSION-unix.tar.gz && \
  rm -f mirthconnect-$MIRTH_CONNECT_VERSION-unix.tar.gz && \
  mv Mirth\ Connect/*  /opt/mirth-connect/ && \
  mv Mirth\ Connect/.install4j /opt/mirth-connect/ && \
  chown -R mirth /opt/mirth-connect

WORKDIR /opt/mirth-connect

EXPOSE 9090 9443

ADD ./mirth.properties /opt/mirth-connect/conf/mirth.properties
ADD ./mirth-cli-config.properties /opt/mirth-connect/conf/mirth-cli-config.properties
ADD ./configuration.properties /opt/mirth-connect/appdata/configuration.properties
ADD ./mirth-config-script.txt /opt/mirth-config-script.txt
ADD ./docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT [ "/docker-entrypoint.sh" ]