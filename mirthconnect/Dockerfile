# Adapted from https://github.com/brandonstevens/mirth-connect-docker
FROM openjdk:8u181-jdk-stretch

ARG ENV_MIRTH_CONNECT_VERSION
ARG ENV_FILEBEAT_VERSION

ENV MIRTH_CONNECT_VERSION ${ENV_MIRTH_CONNECT_VERSION}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    vim \
    postgresql-client \
    netcat \
    nano \
    cron
    
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

EXPOSE 80 8443 6661 6671

ADD ./mirth.properties /opt/mirth-connect/conf/mirth.properties
ADD ./mirth-cli-config.properties /opt/mirth-connect/conf/mirth-cli-config.properties
ADD ./configuration.properties /opt/mirth-connect/appdata/configuration.properties
ADD ./mirth-script_config.txt /opt/mirth-script_config.txt
ADD ./crontab.txt /opt/crontab.txt
ADD ./export-all-channels.sh /opt/export-all-channels.sh
ADD ./mirth-script_export-channels.txt /opt/mirth-script_export-channels.txt
ADD ./docker-entrypoint.sh /docker-entrypoint.sh

###############################################################################
#                                INSTALLATION FILEBEAT
###############################################################################

RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${ENV_FILEBEAT_VERSION}-amd64.deb -O /tmp/filebeat.deb \
 && dpkg -i /tmp/filebeat.deb

ADD filebeat.yml /etc/filebeat/filebeat.yml

###############################################################################


ENTRYPOINT [ "/docker-entrypoint.sh" ]