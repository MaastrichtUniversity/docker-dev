FROM metalnx/metalnx-web:1.0-latest

ADD ./templates.sql /tmp/templates.sql
ADD ./template_fields.sql /tmp/template_fields.sql


ADD ./supervisord.conf /etc/supervisord.conf
ADD ./start_metalnx.sh /start_metalnx.sh

EXPOSE 8080

###############################################################################
#                                INSTALLATION LOGBEAT
###############################################################################

### install Filebeat

#RUN apt-get update -qq \
 #&& apt-get install -qqy curl \
 #&& apt-get clean

RUN curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-5.2.1-x86_64.rpm \
 && rpm -vi filebeat-5.2.1-x86_64.rpm \
 && rm filebeat-5.2.1-x86_64.rpm

###############################################################################
#                                CONFIGURATION LOGBEAT
###############################################################################

### configure Filebeat

# config file
ADD filebeat.yml /etc/filebeat/filebeat.yml


CMD ["/bin/bash", "/start_metalnx.sh"]