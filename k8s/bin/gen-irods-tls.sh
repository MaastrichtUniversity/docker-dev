#!/usr/bin/env bash
# Generates the k8s dev TLS material (test-only, like the committed
# irods/*/test-dev-ssl-certs for the compose stack) into irods/k8s-ssl-certs/.
#
# SANs are the k8s Service FQDNs the pods actually use now (the old
# .dh.local names no longer resolve; see k8s/dh-local-worklist.md):
#   icat.irods.svc.cluster.local
#   ires-hnas-um.irods.svc.cluster.local
#   ires-hnas-azm.irods.svc.cluster.local
#   garage1-s3-tls.irods.svc.cluster.local   (nginx S3 TLS front)
#   garage2-s3-tls.irods.svc.cluster.local
#
# The dev overlay's secretGenerator maps these files to the *old* key names
# (e.g. icat.dh.local.crt) so ENV_IRODS_SSL_CERT/KEY and the garage nginx
# confs need no changes - only the SAN/CN matters.
#
# Usage: k8s/bin/gen-irods-tls.sh [output-dir]   (default: irods/k8s-ssl-certs)
set -euo pipefail

cd "$(dirname "$0")/../.."
OUT="${1:-irods/k8s-ssl-certs}"
mkdir -p "$OUT"

CA_SUBJ="/O=DataHub Maastricht/OU=k8s-dev/CN=DataHub k8s dev test CA"

if [[ ! -f "$OUT/ca.key" ]]; then
    echo "INFO: generating CA"
    openssl genrsa -out "$OUT/ca.key" 2048
    openssl req -x509 -new -nodes -key "$OUT/ca.key" -sha256 -days 3650 \
        -subj "$CA_SUBJ" -out "$OUT/ca.pem"
else
    echo "INFO: reusing existing CA ($OUT/ca.key)"
fi

if [[ ! -f "$OUT/dhparams.pem" ]]; then
    echo "INFO: generating DH params (may take a minute)"
    openssl dhparam -out "$OUT/dhparams.pem" 2048
fi

leaf() {
    local name=$1 fqdn=$2
    echo "INFO: leaf $name ($fqdn)"
    openssl req -new -newkey rsa:2048 -nodes -keyout "$OUT/$name.key" \
        -subj "/O=DataHub Maastricht/OU=k8s-dev/CN=$fqdn" -out "$OUT/$name.csr"
    openssl x509 -req -in "$OUT/$name.csr" \
        -CA "$OUT/ca.pem" -CAkey "$OUT/ca.key" -CAcreateserial \
        -days 3650 -sha256 \
        -extfile <(printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth' "$fqdn") \
        -out "$OUT/$name.crt"
    rm -f "$OUT/$name.csr"
}

NS=irods.svc.cluster.local
leaf icat           "icat.$NS"
leaf ires-hnas-um   "ires-hnas-um.$NS"
leaf ires-hnas-azm  "ires-hnas-azm.$NS"
leaf garage1        "garage1-s3-tls.$NS"
leaf garage2        "garage2-s3-tls.$NS"

echo "OK: TLS material in $OUT/"
ls -1 "$OUT"
