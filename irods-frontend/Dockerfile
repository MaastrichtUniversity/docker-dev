FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    software-properties-common \
    python-software-properties \
    apache2 \
    unzip \
    nodejs \    
    npm \
    git


RUN echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | /usr/bin/debconf-set-selections
RUN apt-add-repository ppa:webupd8team/java && apt-get update && apt-get install oracle-java8-installer -y

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

## Setup Apache reverse proxy for Tomcat
# Enable proxy modules
RUN a2enmod proxy_http
# Add modified apache site-configuration
ADD ./000-default.conf /etc/apache2/sites-available/000-default.conf
ADD ./index.html /var/www/html/index.html

# Add bootstrap script
ADD ./bootstrap.sh /opt/bootstrap.sh 

# Install tomcat8
RUN wget -P /tmp/ http://archive.apache.org/dist/tomcat/tomcat-8/v8.0.35/bin/apache-tomcat-8.0.35.tar.gz \
    && tar xvf /tmp/apache-tomcat-8.0.35.tar.gz -C /tmp/ && mv /tmp/apache-tomcat-8.0.35/ /var/lib/tomcat8

# Install iRODS-REST
RUN wget -P /tmp/ https://code.renci.org/gf/download/frsrelease/243/2742/irods-rest.war \
    && mv /tmp/irods-rest.war /var/lib/tomcat8/webapps/ \
    && mkdir /etc/irods-ext
ADD ./irods-rest.properties /etc/irods-ext/irods-rest.properties

# Install Cloud-Browser config 
ADD ./irods-cloud-backend-config.groovy /etc/irods-cloud-backend-config.groovy
ADD ./irods-cloud-backend-config.groovy /etc/irods-ext/irods-cloud-backend-config.groovy

#Install grails and add to export
RUN cd /tmp \
    && wget https://github.com/grails/grails-core/releases/download/v2.5.0/grails-2.5.0.zip \
    && unzip grails-2.5.0.zip 
    
##Nodejs fix
RUN ln -s /usr/bin/nodejs /usr/bin/node


##Set correct branch for repository 
RUN cd /tmp/irods-cloud-browser/ \
    && git checkout rit-cloud-browser

##exports
ENV JAVA_HOME "/usr/lib/jvm/java-8-oracle"
ENV GRAILS_HOME "/tmp/grails-2.5.0"
ENV PATH "$PATH:$GRAILS_HOME/bin"



EXPOSE 80

ENTRYPOINT [ "/opt/bootstrap.sh" ]
