#!/bin/bash

# Start Tomcat8 service
/var/lib/tomcat8/bin/startup.sh

# this script must end with a persistent foreground process
tail -f /var/lib/tomcat8/logs/catalina.out
#tail -f /var/log/dmesg

