Delete index (collection_metadata) <br>
    `curl -X DELETE -u elastic:$ELASTIC_PASSWORD localhost:9200/collection_metadata?pretty`

Create index (collection_metadata) <br>
    `curl -X PUT -u elastic:$ELASTIC_PASSWORD localhost:9200/collection_metadata?pretty`

Show index content (collection_metadata) <br>
    `curl -X GET -u elastic:$ELASTIC_PASSWORD localhost:9200/collection_metadata/_search`


