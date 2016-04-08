#!/bin/bash

# Start Tomcat8 service
/var/lib/tomcat8/bin/startup.sh

# Force start of apache2 server
service apache2 restart

# this script must end with a persistent foreground process
tail -f /var/lib/tomcat8/logs/catalina.out

