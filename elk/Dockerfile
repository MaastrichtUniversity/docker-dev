FROM sebp/elk:520

ENV LOGSTASH_HOME /opt/logstash

WORKDIR ${LOGSTASH_HOME}
RUN gosu logstash bin/logstash-plugin install logstash-patterns-core
RUN gosu logstash bin/logstash-plugin install logstash-input-beats

RUN cd /etc/logstash && \
    curl -O "http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz" && \
    gunzip GeoLite2-City.mmdb.gz

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    npm
RUN npm install -g elasticdump
RUN ln -s /usr/bin/nodejs /usr/bin/node


ENV XPACK_VERSION 5.2.0
ENV XPACK_PACKAGE x-pack-${XPACK_VERSION}.zip

WORKDIR /tmp
RUN curl -O https://artifacts.elastic.co/downloads/packs/x-pack/${XPACK_PACKAGE} \
 && gosu elasticsearch ${ES_HOME}/bin/elasticsearch-plugin install \
      -Edefault.path.conf=/etc/elasticsearch \
      file:///tmp/${XPACK_PACKAGE} --batch \
 && gosu kibana ${KIBANA_HOME}/bin/kibana-plugin install \
      file:///tmp/${XPACK_PACKAGE} \
 && rm -f ${XPACK_PACKAGE}

###Logtrail
RUN /opt/kibana/bin/kibana-plugin install https://github.com/sivasamyk/logtrail/releases/download/0.1.8/logtrail-5.2.0-0.1.8.zip
ADD logtrail.json /opt/kibana/plugins/logtrail/logtrail.json

# Add config files
ADD FRONTEND.conf /etc/logstash/conf.d/FRONTEND.conf
ADD ICAT.conf /etc/logstash/conf.d/ICAT.conf
ADD IRES.conf /etc/logstash/conf.d/IRES.conf
ADD IRODS_FRONTEND.conf /etc/logstash/conf.d/IRODS_FRONTEND.conf
ADD METALNX.conf /etc/logstash/conf.d/METALNX.conf
ADD MIRTH.conf /etc/logstash/conf.d/MIRTH.conf
ADD PACMAN.conf /etc/logstash/conf.d/PACMAN.conf
ADD PROXY.conf /etc/logstash/conf.d/PROXY.conf
ADD SOLR.conf /etc/logstash/conf.d/SOLR.conf
ADD 30-output.conf /etc/logstash/conf.d/30-output.conf

ADD ./RIT.pattern ${LOGSTASH_HOME}/patterns/RIT
ADD ./kibana-exported.json /tmp/kibana-exported.json


EXPOSE 5000 5555

#Create own startup script
ADD ./start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

#
CMD [ "/usr/local/bin/start.sh" ]


## Create dashboard dump

#elasticdump --input=http://elastic:changeme@localhost:9200/.kibana --output=$ --type=data > kibana-exported.json

#Load dahsboard dump
# cd tmp
# elasticdump --input=kibana-exported.json --output=http://localhost:9200/.kibana --type=data