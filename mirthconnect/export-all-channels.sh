#! /bin/bash

TIMESTAMP=`/bin/date "+%Y-%m-%d-%H_%M"`;

/opt/mirth-connect/mccommand -s /opt/mirth-script_export-channels.txt

tar -czf /opt/channels-backup/channels_${TIMESTAMP}.tar.gz /tmp/channels
rm -r /tmp/channels/
