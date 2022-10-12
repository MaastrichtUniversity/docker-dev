FROM elasticsearch:7.17.6

ADD bootstrap_elastic_dh.sh /tmp/bootstrap_elastic_dh.sh
ADD create_irods_index.sh /tmp/create_irods_index.sh

RUN chmod +x /tmp/bootstrap_elastic_dh.sh
RUN chmod +x /tmp/create_irods_index.sh

CMD ["/tmp/bootstrap_elastic_dh.sh"]
