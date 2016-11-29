FROM sebp/elk:es241_l240_k461

ENV LOGSTASH_HOME /opt/logstash

WORKDIR ${LOGSTASH_HOME}
RUN gosu logstash bin/logstash-plugin install logstash-patterns-core

ENV ES_HOME /usr/share/elasticsearch
WORKDIR ${ES_HOME}

RUN gosu elasticsearch bin/plugin install royrusso/elasticsearch-HQ

RUN cd /etc/logstash && \
    curl -O "http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz" && \
    gunzip GeoLiteCity.dat.gz

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    npm
RUN npm install -g elasticdump
RUN ln -s /usr/bin/nodejs /usr/bin/node

###Logtrail
RUN /opt/kibana/bin/kibana plugin -i logtrail -u https://github.com/sivasamyk/logtrail/releases/download/0.1.5/logtrail-4.x-0.1.5.tar.gz
ADD logtrail.json /opt/kibana/installedPlugins/logtrail/logtrail.json

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
ADD IO.conf /etc/logstash/conf.d/IO.conf

ADD ./RIT.pattern ${LOGSTASH_HOME}/patterns/RIT
ADD ./kibana-exported.json /tmp/kibana-exported.json

EXPOSE 5000

##Create own startup script
ADD ./start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

CMD [ "/usr/local/bin/start.sh" ]


## Create dashboard dump 

#elasticdump --input=http://localhost:9200/.kibana --output=$ --type=data --searchBody='{"filter": { "or": [ {"type": {"value": "dashboard"}}, {"type": {"value": "search"}},{"type" : {"value":"visualization"}}] }}' > kibana-exported.json

#Load dahsboard dump
# cd tmp 
# elasticdump --input=kibana-exported.json --output=http://localhost:9200/.kibana --type=data