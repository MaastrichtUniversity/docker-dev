FROM python:3.10

# install packages for this iRES
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nano

ARG PIP_PACKAGE="irods-capability-automated-ingest"

RUN pip install ${PIP_PACKAGE}

RUN mkdir -p /var/lib/irods

COPY ./config/irods_environment.json /var/lib/irods/irods_environment.json
COPY ./scripts/event_handler.py /var/lib/irods/event_handler.py

ADD ./test-dev-ssl-certs/test_only_dev_irods_dh_ca_cert.pem /tmp/test_only_dev_irods_dh_ca_cert.pem

# SSL Patch required for our Setup against the irods ingest framework
ADD ./patch/Update_ssl_settings.patch /var/lib/irods/Update_ssl_settings.patch
ADD ./patch/Add_failure_check.patch /var/lib/irods/Add_failure_check.patch


RUN echo "Adding custom DataHub iRODS-CA-certificate to the CA-rootstore (FOR DEV & TEST ONLY!)..." ; \
        cp /tmp/test_only_dev_irods_dh_ca_cert.pem /usr/local/share/ca-certificates/test_only_dev_irods_dh_ca_cert.crt ; \
        update-ca-certificates

RUN patch /usr/local/lib/python3.10/site-packages/irods_capability_automated_ingest/sync_irods.py /var/lib/irods/Update_ssl_settings.patch
RUN patch /usr/local/lib/python3.10/site-packages/irods_capability_automated_ingest/sync_actions.py /var/lib/irods/Add_failure_check.patch

EXPOSE 5000

ENTRYPOINT ["irods_capability_automated_ingest"]
CMD ["-h"]
