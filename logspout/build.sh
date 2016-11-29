#!/bin/sh
set -e
apk add --update go git mercurial build-base
mkdir -p /go/src/github.com/gliderlabs
mkdir -p /go/src/github.com/go-check
export GOPATH=/go
go get gopkg.in/check.v1
ln -sT /go/src/gopkg.in/check.v1 /go/src/github.com/go-check/check
cp -r /src /go/src/github.com/gliderlabs/logspout
cd /go/src/github.com/gliderlabs/logspout

go get
go build -ldflags "-X main.Version $1" -o /bin/logspout
apk del go git mercurial build-base
rm -rf /go
rm -rf /var/cache/apk/*

# backwards compatibility
ln -fs /tmp/docker.sock /var/run/docker.sock
