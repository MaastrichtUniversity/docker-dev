FROM python:3.6

WORKDIR /opt/app

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    libldap2-dev \
    libsasl2-dev \
    libssl-dev

# Python requirements
ADD requirements.txt /opt
RUN pip install -r /opt/requirements.txt

# Entry point
ADD bootstrap.sh /opt
RUN chmod +x /opt/bootstrap.sh

VOLUME ["/input", "/output"]
ENTRYPOINT [ "/opt/bootstrap.sh" ]