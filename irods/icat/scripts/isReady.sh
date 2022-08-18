#!/bin/bash

filename=/tmp/isReady.log
if test -f "$filename";
then
    echo "$file has found."
    exit 0
else
    echo "$file has not been found"
    exit 1
fi