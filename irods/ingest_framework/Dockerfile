FROM python:3.10

ARG PIP_PACKAGE="irods-capability-automated-ingest"

RUN pip install ${PIP_PACKAGE}

COPY ./config/irods_environment.json /

ADD ./test-dev-ssl-certs/test_only_dev_irods_dh_ca_cert.pem /tmp/test_only_dev_irods_dh_ca_cert.pem

# SSL Patch required for our Setup against the irods ingest framework
ADD ./patch/Update_ssl_settings.patch /tmp/Update_ssl_settings.patch

RUN echo "Adding custom DataHub iRODS-CA-certificate to the CA-rootstore (FOR DEV & TEST ONLY!)..." ; \
        cp /tmp/test_only_dev_irods_dh_ca_cert.pem /usr/local/share/ca-certificates/test_only_dev_irods_dh_ca_cert.crt ; \
        update-ca-certificates

RUN patch /usr/local/lib/python3.10/site-packages/irods_capability_automated_ingest/sync_irods.py /tmp/Update_ssl_settings.patch

ENTRYPOINT ["irods_capability_automated_ingest"]
CMD ["-h"]
