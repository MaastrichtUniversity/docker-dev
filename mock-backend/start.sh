#!/bin/sh
set -eu
umask 077

if [ ! -s "$MOCK_SERVER_CERT" ] || [ ! -s "$MOCK_SERVER_KEY" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -subj /CN=mock-backend \
        -addext subjectAltName=DNS:mock-backend,DNS:localhost,IP:127.0.0.1 \
        -keyout "$MOCK_SERVER_KEY" -out "$MOCK_SERVER_CERT"
fi
# Share only the trust certificate with clients, never the private key.
install -m 644 "$MOCK_SERVER_CERT" /mock-ca/ca.pem.tmp
mv /mock-ca/ca.pem.tmp /mock-ca/ca.pem
exec python /app/server.py
