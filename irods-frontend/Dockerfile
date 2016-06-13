FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    software-properties-common \
    python-software-properties \
    apache2 \
    unzip \
    nodejs \    
    npm 


RUN echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | /usr/bin/debconf-set-selections
RUN apt-add-repository ppa:webupd8team/java && apt-get update && apt-get install oracle-java8-installer -y

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

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

# Install Cloud-Browser backend
RUN wget -P /var/lib/tomcat8/webapps/ https://code.renci.org/gf/download/frsrelease/239/2717/irods-cloud-backend.war
ADD ./irods-cloud-backend-config.groovy /etc/irods-cloud-backend-config.groovy

# Install Cloud-Browser frontend
RUN wget -P /tmp/ https://code.renci.org/gf/download/frsrelease/239/2712/irods-cloud-frontend.zip \
    && unzip /tmp/irods-cloud-frontend.zip -d /var/www/html/
### MUMC-modified version of Cloud browser. Uncomment the following lines if necessary. ###
#ADD ./irods-cloud-frontend-1.0.0-RELEASE_MUMC.zip /tmp/irods-cloud-frontend-1.0.0-RELEASE_MUMC.zip
#RUN unzip /tmp/irods-cloud-frontend-1.0.0-RELEASE_MUMC.zip -d /var/www/html/

EXPOSE 8080 80

ENTRYPOINT [ "/opt/bootstrap.sh" ]
