Delete index (irods) <br>
    `curl -X DELETE -u elastic:$ELASTIC_PASSWORD localhost:9200/irods?pretty`

Create index (irods) <br>
    `curl -X PUT -u elastic:$ELASTIC_PASSWORD localhost:9200/irods?pretty`

Show index content (irods) <br>
    `curl -X GET -u elastic:$ELASTIC_PASSWORD localhost:9200/irods/_search`


