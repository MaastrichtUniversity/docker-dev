FROM elasticsearch:7.17.6

ADD bootstrap_elastic_dh.sh /tmp/bootstrap_elastic_dh.sh
ADD create_collection_metadata_index.sh /tmp/create_collection_metadata_index.sh

RUN chmod +x /tmp/bootstrap_elastic_dh.sh
RUN chmod +x /tmp/create_collection_metadata_index.sh

CMD ["/tmp/bootstrap_elastic_dh.sh"]
