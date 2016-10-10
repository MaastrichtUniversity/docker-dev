#!/bin/bash

## run npm install
cd /tmp/irods-cloud-browser/irods-cloud-frontend
npm install --unsafe-perm 
npm install --global gulp-cli
     
## run gulp builds 
gulp backend-build
gulp gen-war
gulp gen-war


cp /tmp/irods-cloud-browser/build/irods-cloud-backend.war /var/lib/tomcat8/webapps/

# Start Tomcat8 service
/var/lib/tomcat8/bin/startup.sh

# Force start of apache2 server
rm -f /var/run/apache2/apache2.pid
service apache2 start

# this script must end with a persistent foreground process
tail -f /var/lib/tomcat8/logs/catalina.out

