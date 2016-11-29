#!/bin/sh

set -e

echo $1
a=0
b=1
while [ $a -lt 10 ]
do
  b=$(nc -z -v -u elk 5000 &> /dev/null; echo $?)
  if [ $b == "0" ]; then
  	echo "server reachable"
   /bin/logspout $1
  else
  	echo "server not reachable"
   sleep 10
    a=`expr $a + 1`
  fi
done


exit 1

