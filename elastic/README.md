# Delete index (collection_metadata) <br>  
    # Inside the elastic container  
    curl -X DELETE -u elastic:$ELASTIC_PASSWORD localhost:9200/collection_metadata?pretty  
    # outside the elastic container  
    curl -X DELETE -u elastic:$ELASTIC_PASSWORD elastic.local.dh.unimaas.nl/collection_metadata?pretty  
# Create index (collection_metadata) <br>  
    # Inside the elastic container  
    curl -X PUT -u elastic:$ELASTIC_PASSWORD localhost:9200/collection_metadata?pretty  
    # outside the elastic container  
    curl -X PUT -u elastic:$ELASTIC_PASSWORD elastic.local.dh.unimaas.nl/collection_metadata?pretty  
# Show index content (collection_metadata) <br>  
    # Inside the elastic container  
    curl -X GET -u elastic:$ELASTIC_PASSWORD localhost:9200/collection_metadata/_search  
    # outside the elastic container  
    curl -X GET -u elastic:$ELASTIC_PASSWORD elastic.local.dh.unimaas.nl/collection_metadata/_search
