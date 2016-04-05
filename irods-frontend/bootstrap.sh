#!/bin/bash

# Start Tomcat8 service
/var/lib/tomcat8/bin/startup.sh

# Force start of apache2 server
service apache2 restart

# Dynamically fill the backend hostname in globals.js with ENV variable from docker-compose.yml
# TIP: Since hostname contains forward slashes, use | as separator in sed statement
sed -i "s|+location.hostname+|$FQDN_HOST|" /var/www/html/irods-cloud-frontend/app/components/globals.js

# this script must end with a persistent foreground process
tail -f /var/lib/tomcat8/logs/catalina.out

