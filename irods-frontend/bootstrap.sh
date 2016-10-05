#!/bin/bash

# Start Tomcat8 service
/var/lib/tomcat8/bin/startup.sh

# Force start of apache2 server
rm -f /var/run/apache2/apache2.pid
service apache2 start

# this script must end with a persistent foreground process
tail -f /var/lib/tomcat8/logs/catalina.out

