FROM centos:7

RUN yum install -y \
    # extra repository to download extra packages
    epel-release \
    # backwards compatibility for service command
    initscripts \
    sudo

RUN yum install -y \
    wget \
    unixODBC \
#    super \
    fuse-libs \
    perl-JSON \
    python \
    python-psutil \
    python-requests \
    python-jsonschema \
    python-ldap \
    lsof \
    make \
    nano \
    cifs-utils  \
    gcc-c++ \
    openssl \
    openssl-devel \
    libcurl-devel \
    curl


#RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV IRODS_VERSION 4.1.8

# install iRODS
RUN wget ftp://ftp.renci.org/pub/irods/releases/${IRODS_VERSION}/centos7/irods-resource-${IRODS_VERSION}-centos7-x86_64.rpm -O /tmp/irods-ires.rpm \
    && rpm -Uvh /tmp/irods-ires.rpm

RUN wget ftp://ftp.renci.org/pub/irods/releases/${IRODS_VERSION}/centos7/irods-dev-${IRODS_VERSION}-centos7-x86_64.rpm -O /tmp/irods-dev.rpm \
    && rpm -Uvh /tmp/irods-dev.rpm

# install Metalnx RMD
#RUN wget https://bintray.com/metalnx/rpm/download_file?file_path=emc-metalnx-rmd-1.0-22.noarch.rpm -O /tmp/emc-metalnx-rmd.rpm \
#    && rpm -Uvh /tmp/emc-metalnx-rmd.rpm

RUN mkdir /opt/irods
#
## Bug in cifs-utils package causes setcifsacl not to work without setting this symlink
## https://bugs.launchpad.net/ubuntu/+source/cifs-utils/+bug/1372120
#RUN mkdir /etc/cifs-utils && ln -s /usr/lib/x86_64-linux-gnu/cifs-utils/idmapwb.so /etc/cifs-utils/idmap-plugin
#
ADD ./setup_responses /etc/irods/setup_responses
ADD ./config.sh /opt/irods/config.sh
ADD ./bootstrap.sh /opt/irods/bootstrap.sh
ADD ./bootstrap_irods.sh /opt/irods/bootstrap_irods.sh
ADD ./prepend_ruleset.py /opt/irods/prepend_ruleset.py
ADD ./add_env_var.py /opt/irods/add_env_var.py
RUN chmod a+x /opt/irods/*

EXPOSE 1248 1247 8000


###############################################################################
#                                INSTALLATION FILEBEAT
###############################################################################

RUN wget https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-5.2.0-x86_64.rpm -O /tmp/filebeat.rpm \
 && rpm -Uvh /tmp/filebeat.rpm

ADD filebeat.yml /etc/filebeat/filebeat.yml

###############################################################################


##############################################################################################
# [RPMBUILD] Uncomment the part below to use this CentOS as an RPM build- and package-server #
##############################################################################################

RUN yum install -y \
    # For building RPMs
    autoconf automake \
    rpm-build rpmdevtools rpmlint \
    # Dependencies for building cifs-utils
    libtalloc-devel \
    libwbclient-devel

###################################################################################

ENV DOCKERIZE_VERSION v0.2.0
RUN curl -fSL https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz -o dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz

CMD dockerize -wait tcp://ires:1248 -timeout 150s /opt/irods/bootstrap.sh