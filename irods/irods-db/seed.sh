#!/usr/bin/env bash
# Host-side catalog snapshot support. Run from rit.sh; no container images change.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

export RIT_ENV="${RIT_ENV:-local}"
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-dev}"
compose_command=(docker compose -f docker-compose.yml -f docker-compose-irods.yml)
seed_dir=irods/irods-db/seed

compose() { "${compose_command[@]}" "$@"; }

current_config() {
    compose --profile full config --format json | python3 irods/irods-db/seed_config.py generate
}

compare_config() {
    if ! python3 irods/irods-db/seed_config.py compare "$1" "$2"; then
        echo "ERROR: Reset with ./rit.sh backend --reset --fresh, or rebuild the seed and run ./rit.sh backend --reset." >&2
        return 1
    fi
}

read_catalog_config() {
    docker cp "$1:$2/$3" - 2>/dev/null | tar -xO 2>/dev/null
}

write_catalog_config() {
    printf '%s\n' "$1" | compose exec -T irods-db sh -c '
        cat > "$PGDATA/$1.tmp" && mv "$PGDATA/$1.tmp" "$PGDATA/$1"
    ' sh "$2"
}

check_seed() {
    local expected=$1
    if [[ ! -f "$seed_dir/config.json" || ! -f "$seed_dir/icat.dump.sha256" ]]; then
        echo "ERROR: No compatible catalog seed available. Run ./rit.sh seed rebuild, or ./rit.sh backend --reset --fresh." >&2
        return 1
    fi
    compare_config "$(cat "$seed_dir/config.json")" "$expected"
    if ! (cd "$seed_dir" && sha256sum --check --status icat.dump.sha256); then
        echo "ERROR: Catalog seed is damaged. Run ./rit.sh seed rebuild." >&2
        return 1
    fi
}

catalog_sql() {
    compose exec -T irods-db sh -c '
        export PGPASSWORD="$POSTGRES_PASSWORD"
        exec psql -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" \
            -d "$ENV_IRODS_DB_NAME" -XAt -v ON_ERROR_STOP=1 -c "$1"
    ' sh "$1"
}

wait_ready() {
    local service=$1 deadline=$((SECONDS + 600))
    while (( SECONDS < deadline )); do
        if [[ "$service" == irods-db ]]; then
            if catalog_sql 'SELECT 1' >/dev/null 2>&1; then return 0; fi
        elif compose exec -T "$service" /dh_is_ready.sh >/dev/null 2>&1; then
            return 0
        fi
        if [[ "$(compose ps -a --format '{{.State}}' "$service")" == exited ]]; then
            break
        fi
        echo "Waiting for $service"
        sleep 5
    done
    echo "ERROR: $service did not become ready; recent logs follow." >&2
    compose logs --tail 40 "$service" >&2
    return 1
}

verify_seed() {
    # The baseline has nine empty projects and five successful bootstrap markers.
    local valid
    valid=$(catalog_sql "SELECT
        (SELECT count(*) FROM r_coll_main
         WHERE parent_coll_name = '/nlmumc/projects'
           AND coll_name ~ '^/nlmumc/projects/P[0-9]{9}$') = 9
        AND (SELECT count(*) FROM r_data_main) = 0
        AND (SELECT count(*) FROM r_resc_main r
             JOIN r_objt_metamap m ON m.object_id = r.resc_id
             JOIN r_meta_main a ON a.meta_id = m.meta_id
             WHERE r.resc_name IN ('rootResc', 'passRescUM01', 'replRescAZM02',
                                   'UM-Ceph-S3-AC', 'UM-Ceph-S3-GL')
               AND a.meta_attr_name = 'bootstrap_irods_dev_mockup'
               AND a.meta_attr_value = 'complete') = 5")
    if [[ "$valid" != t ]]; then
        echo "ERROR: Expected nine empty projects and all bootstrap markers completed." >&2
        return 1
    fi
}

prepare() {
    local mode=$1 tables expected db_id pgdata recorded state=empty
    expected=$(current_config)
    if [[ -n "$expected" ]]; then
        # Read the old container's mounted PGDATA before Compose can change its image.
        db_id=$(compose ps -a -q irods-db)
        if [[ -n "$db_id" ]]; then
            pgdata=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$db_id" | sed -n 's/^PGDATA=//p')
            if recorded=$(read_catalog_config "$db_id" "$pgdata" dh-dev-config.pending.json); then
                state=pending
            elif recorded=$(read_catalog_config "$db_id" "$pgdata" dh-dev-config.json); then
                state=ready
            else
                echo "ERROR: Existing development database has no recorded creation configuration. Use ./rit.sh backend --reset --fresh, or rebuild the seed and use ./rit.sh backend --reset." >&2
                return 1
            fi
            compare_config "$recorded" "$expected"
        fi
    fi
    compose up -d irods-db
    wait_ready irods-db
    if [[ -z "$expected" ]]; then
        echo "Development catalog checks and seeding are disabled outside dev."
        return 0
    fi
    tables=$(catalog_sql "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'")
    if [[ "$tables" != 0 ]]; then
        if [[ "$state" != ready ]]; then
            echo "ERROR: Development catalog initialization did not finish. Use ./rit.sh backend --reset --fresh, or rebuild the seed and use ./rit.sh backend --reset." >&2
            return 1
        fi
        if [[ "$mode" == fresh ]]; then
            echo "ERROR: --fresh requires an empty catalog. Use ./rit.sh backend --reset --fresh to discard existing iRODS development state." >&2
            return 1
        fi
        echo "Using the existing iRODS catalog."
        return 0
    fi
    write_catalog_config "$expected" dh-dev-config.pending.json
    if [[ "$mode" == fresh ]]; then
        echo "Fresh catalog: the normal bootstrap scripts will populate it."
        return 0
    fi

    check_seed "$expected"
    echo "Restoring the default iRODS catalog seed."
    compose exec -T irods-db sh -c '
        export PGPASSWORD="$ENV_IRODS_DB_IRODS_PASSWORD"
        exec pg_restore -h 127.0.0.1 --username "$ENV_IRODS_DB_USERNAME" \
            --dbname "$ENV_IRODS_DB_NAME" --no-owner --exit-on-error --single-transaction
    ' < "$seed_dir/icat.dump"
    verify_seed
    complete
}

complete() {
    local expected recorded db_id pgdata
    expected=$(current_config)
    [[ -n "$expected" ]] || return 0
    db_id=$(compose ps -a -q irods-db)
    pgdata=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$db_id" | sed -n 's/^PGDATA=//p')
    if recorded=$(read_catalog_config "$db_id" "$pgdata" dh-dev-config.pending.json); then
        compare_config "$recorded" "$expected"
        compose exec -T irods-db sh -c 'mv "$PGDATA/dh-dev-config.pending.json" "$PGDATA/dh-dev-config.json"'
    else
        recorded=$(read_catalog_config "$db_id" "$pgdata" dh-dev-config.json)
        compare_config "$recorded" "$expected"
    fi
}

reset() {
    # Remove only iRODS containers and their anonymous volumes. Keep other apps
    # and the host's mounted ingest directories intact.
    local services=(sram-sync icat ires-hnas-um ires-hnas-azm irods-db
                    garage1-s3-tls garage2-s3-tls garage-init garage1 garage2)
    echo "Resetting the iRODS development catalog, container vaults and Garage storage."
    compose stop "${services[@]}"
    compose rm -f -v "${services[@]}"
}

rebuild() (
    local work_dir project
    export ENV_IRODS_WAIT_FOR_CATALOG=false
    work_dir=$(mktemp -d)
    project="irods-seed-$$"
    compose_command=(docker compose -p "$project" -f docker-compose-irods.yml
                     -f "$work_dir/compose.yml" --profile full)
    trap 'compose down --volumes --remove-orphans >/dev/null; rm -rf "$work_dir"' EXIT
    # Separate networks, no published ports and no host ingest mounts.
    cat > "$work_dir/compose.yml" <<EOF
services:
  icat:
    ports: !reset []
  ires-hnas-um:
    volumes:
      - /mnt/ingest/zones
      - /mnt/stagingResc01
networks:
  dh_default:
    external: false
    name: ${project}_default
EOF
    current_config > "$work_dir/config.json"
    [[ -s "$work_dir/config.json" ]] || { echo "ERROR: Seeds can only be built for dev." >&2; exit 1; }
    prepare fresh
    compose up -d icat
    wait_ready icat
    # Fixed ordering gives the baseline reproducible project numbers.
    compose up -d ires-hnas-um
    wait_ready ires-hnas-um
    compose up -d ires-hnas-azm
    wait_ready ires-hnas-azm
    verify_seed
    complete
    compare_config "$(cat "$work_dir/config.json")" "$(current_config)"
    compose exec -T irods-db sh -c '
        export PGPASSWORD="$ENV_IRODS_DB_IRODS_PASSWORD"
        exec pg_dump -h 127.0.0.1 --username "$ENV_IRODS_DB_USERNAME" \
            --dbname "$ENV_IRODS_DB_NAME" --format=custom
    ' > "$work_dir/icat.dump"
    (cd "$work_dir" && sha256sum icat.dump > icat.dump.sha256)
    mkdir -p "$seed_dir"
    mv "$work_dir/icat.dump" "$work_dir/icat.dump.sha256" "$work_dir/config.json" "$seed_dir/"
    rm -f "$seed_dir/inputs.sha256"
    echo "Default catalog seed rebuilt in $seed_dir."
)

case "${1:-}" in
    prepare)
        [[ "${2:-}" == fresh || "${2:-}" == snapshot ]] || exit 2
        prepare "$2"
        ;;
    reset) reset ;;
    complete) complete ;;
    check-seed)
        expected=$(current_config)
        [[ -z "$expected" ]] || check_seed "$expected"
        ;;
    rebuild) rebuild ;;
    *) echo "Usage: $0 {prepare snapshot|prepare fresh|complete|check-seed|reset|rebuild}" >&2; exit 2 ;;
esac
