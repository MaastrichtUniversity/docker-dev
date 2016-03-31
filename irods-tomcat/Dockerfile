FROM ubuntu:14.04

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    lsof \
    make \
    cifs-utils \
    software-properties-common \
    python-software-properties

RUN echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | /usr/bin/debconf-set-selections
RUN apt-add-repository ppa:webupd8team/java && apt-get update && apt-get install oracle-java8-installer -y

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Add bootstrap script
ADD ./bootstrap.sh /opt/bootstrap.sh 

# Install iRODS-REST
RUN wget -P /tmp/ http://apache.mirror1.spango.com/tomcat/tomcat-8/v8.0.33/bin/apache-tomcat-8.0.33.tar.gz
RUN wget -P /tmp/ https://code.renci.org/gf/download/frsrelease/243/2742/irods-rest.war
RUN tar xvf /tmp/apache-tomcat-8.0.33.tar.gz -C /tmp/ && mv /tmp/apache-tomcat-8.0.33/ /var/lib/tomcat8
RUN mv /tmp/irods-rest.war /var/lib/tomcat8/webapps/ && mkdir /etc/irods-ext
ADD ./irods-rest.properties /etc/irods-ext/irods-rest.properties

# Install Cloud-Browser backend
RUN wget -P /var/lib/tomcat8/webapps/ https://code.renci.org/gf/download/frsrelease/239/2717/irods-cloud-backend.war
ADD ./irods-cloud-backend-config.groovy /etc/irods-cloud-backend-config.groovy

EXPOSE 8080

ENTRYPOINT [ "/opt/bootstrap.sh" ]
