#!/bin/sh
set -eu

bucket="${GARAGE_BUCKET:-dh-irods-bucket-dev}"
marker=/var/lib/garage-bootstrap/initialized
garage="/garage --rpc-secret ${GARAGE_RPC_SECRET}"

wait_for_node_id() {
    config_file=$1
    node_name=$2

    until node_id=$(/garage -c "$config_file" node id -q 2>/dev/null); do
        echo "INFO: Waiting for $node_name node id" >&2
        sleep 2
    done

    echo "$node_id"
}

wait_for_rpc() {
    rpc_host=$1

    until $garage --rpc-host "$rpc_host" status >/dev/null 2>&1; do
        echo "INFO: Waiting for Garage RPC at $rpc_host"
        sleep 2
    done
}

garage1_id=$(wait_for_node_id /etc/garage/garage1.toml garage1)
garage2_id=$(wait_for_node_id /etc/garage/garage2.toml garage2)
garage1_node=${garage1_id%%@*}
garage2_node=${garage2_id%%@*}

wait_for_rpc "$garage1_id"

echo "INFO: Connecting Garage nodes"
$garage --rpc-host "$garage1_id" node connect "$garage2_id" || true

if [ -f "$marker" ]; then
    echo "INFO: Garage cluster already initialized"
    exit 0
fi

echo "INFO: Creating Garage layout"
$garage --rpc-host "$garage1_id" layout assign "$garage1_node" -z garage-dev-1 -c 1G -t garage1
$garage --rpc-host "$garage1_id" layout assign "$garage2_node" -z garage-dev-2 -c 1G -t garage2
$garage --rpc-host "$garage1_id" layout apply --version 1

echo "INFO: Creating Garage bucket and iRODS S3 keys"
$garage --rpc-host "$garage1_id" bucket info "$bucket" >/dev/null 2>&1 || \
    $garage --rpc-host "$garage1_id" bucket create "$bucket"

$garage --rpc-host "$garage1_id" key info "$ENV_S3_ACCESS_KEY_AC" >/dev/null 2>&1 || \
    $garage --rpc-host "$garage1_id" key import "$ENV_S3_ACCESS_KEY_AC" "$ENV_S3_SECRET_KEY_AC" -n irods-ac --yes
$garage --rpc-host "$garage1_id" key info "$ENV_S3_ACCESS_KEY_GL" >/dev/null 2>&1 || \
    $garage --rpc-host "$garage1_id" key import "$ENV_S3_ACCESS_KEY_GL" "$ENV_S3_SECRET_KEY_GL" -n irods-gl --yes

$garage --rpc-host "$garage1_id" bucket allow "$bucket" --key "$ENV_S3_ACCESS_KEY_AC" --read --write --owner
$garage --rpc-host "$garage1_id" bucket allow "$bucket" --key "$ENV_S3_ACCESS_KEY_GL" --read --write --owner

mkdir -p "$(dirname "$marker")"
date -u +%Y-%m-%dT%H:%M:%SZ > "$marker"
echo "INFO: Garage cluster initialized"
