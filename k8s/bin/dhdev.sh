#!/usr/bin/env bash
# Day-2 helper for the k8s dev overlay on a local minikube cluster.
#
#   k8s/bin/dhdev.sh externals   one-time (and refresh): create externals/
#                                at the repo root and clone/pull the app
#                                repos (same list as the compose repo's
#                                rit.sh). Also checks for the SURF
#                                credentials the dev overlay embeds for
#                                epicpid - those are NOT in the public
#                                epicpid-microservice repo and must be
#                                placed manually (the script says where).
#
#   k8s/bin/dhdev.sh pull-external
#                                pull the upstream external images (postgres,
#                                garage, openldap, nginx, traefik) into
#                                minikube's Docker daemon so imagePullPolicy:
#                                Never works for every pod.
#
#   k8s/bin/dhdev.sh build       build all compose images directly inside
#                                minikube's Docker daemon, keeping the
#                                registry.prod.dh.unimaas.nl/docker-dev/*:latest
#                                tags (so they can be pushed when needed) without
#                                pulling from the remote registry. Supports
#                                --profile <full|minimal> [service...].
#
#   k8s/bin/dhdev.sh dev-up      spin up / refresh the dev overlay on
#                                local minikube: externals check, minikube
#                                (4 CPU / 8Gi / 80Gi), external image pulls +
#                                local image build (skip with --no-build),
#                                loadbalancer addon, Traefik with Gateway API
#                                (minikube-traefik.sh), apply of the dev overlay,
#                                readiness checks. Idempotent - re-run
#                                after a git pull to roll out changes.
#
#                                --profile <full|minimal> (default full):
#                                'minimal' is the compose 'minimal' set -
#                                iRODS (db, icat, ires-um, garage), keycloak,
#                                ldap, epicpid, elastic, mdr - and skips the
#                                full-only workloads (ires-hnas-azm, davrods,
#                                help-center, dh-home, admin-tools, ...).
#                                Switching back to 'full' re-adds them; it
#                                never deletes workloads of a bigger
#                                previous profile.
#
# Usage:  k8s/bin/dhdev.sh <externals|pull-external|build [--profile full|minimal] [svc...]|dev-up [--profile full|minimal] [--no-build]|help>
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
EXTERNALS_DIR=$REPO_ROOT/externals
SURF_DIR=$EXTERNALS_DIR/epicpid-microservice/credentials
SURF_FILES="305_21_T12996_USER01_UM_privkey.pem
305_21_T12996_USER01_UM_certificate_only.pem"

# Same list as the compose repo's rit.sh (its `externals=` variable).
EXTERNALS="irods-helper-cmd https://github.com/MaastrichtUniversity/irods-helper-cmd.git
irods-ruleset https://github.com/MaastrichtUniversity/irods-ruleset.git
rit-davrods https://github.com/MaastrichtUniversity/rit-davrods.git
epicpid-microservice https://github.com/MaastrichtUniversity/epicpid-microservice.git
dh-mdr https://github.com/MaastrichtUniversity/dh-mdr.git
irods-rule-wrapper https://github.com/MaastrichtUniversity/irods-rule-wrapper.git
sram-sync https://github.com/MaastrichtUniversity/sram-sync.git
dh-faker https://github.com/MaastrichtUniversity/dh-faker.git
dh-irods https://github.com/MaastrichtUniversity/dh-irods.git
dh-python-irods-utils https://github.com/MaastrichtUniversity/dh-python-irods-utils.git
cedar-parsing-utils https://github.com/MaastrichtUniversity/cedar-parsing-utils.git
dh-elasticsearch https://github.com/MaastrichtUniversity/dh-elasticsearch.git
dh-help-center https://github.com/MaastrichtUniversity/dh-help-center.git
dh-admin-tools https://github.com/MaastrichtUniversity/dh-admin-tools
dh-home https://github.com/MaastrichtUniversity/dh-home
dh-mdr-home https://github.com/MaastrichtUniversity/dh-mdr-home"

cmd_externals() {
  local fail=0
  while read -r name url; do
    [ -z "$name" ] && continue
    if [ -d "$EXTERNALS_DIR/$name/.git" ]; then
      if git -C "$EXTERNALS_DIR/$name" pull --ff-only --quiet 2>/dev/null; then
        echo "  pull   $name"
      else
        echo "  WARNING: $name - pull failed (dirty tree or no upstream), keeping as-is" >&2
      fi
    else
      echo "  clone  $name"
      git clone --quiet "$url" "$EXTERNALS_DIR/$name" || {
        echo "  ERROR: clone of $url failed" >&2
        fail=1
      }
    fi
  done <<< "$EXTERNALS"

  # The dev overlay embeds these SURF files for the epicpid credentials
  # Secret; they are untracked in the public epicpid-microservice repo, so
  # a fresh clone does not contain them.
  local missing=0 f
  for f in $SURF_FILES; do
    if [ ! -f "$SURF_DIR/$f" ]; then
      missing=1
      echo "  MISSING: $SURF_DIR/$f" >&2
    fi
  done
  if [ "$missing" = 1 ]; then
    cat >&2 <<'EOF'

The SURF credentials for epicpid are NOT committed in the public
epicpid-microservice repo, so a fresh clone lacks them. Copy them from an
existing checkout, e.g. your compose tree:

  cp <compose-tree>/externals/epicpid-microservice/credentials/*.pem \
     externals/epicpid-microservice/credentials/

(They must exist before the dev overlay can be built.)
EOF
  fi
  [ "$fail" = 1 ] && return 1
  [ "$missing" = 1 ] && return 1
  return 0
}

# minikube start's --cpus/--memory/--disk-size only apply when the profile
# is CREATED. An existing profile (running or stopped) keeps its old size,
# so verify it is big enough for the dev overlay (sum of pod requests:
# 2.45 CPU / 6Gi) before starting.
check_minikube_size() {
  command -v jq >/dev/null || return 0
  local profile=${MINIKUBE_PROFILE:-minikube} spec
  spec=$(minikube profile list -o json 2>/dev/null \
    | jq -r --arg p "$profile" '.[].Profile | select(.Name==$p) | "\(.CPUs) \(.Memory) \(.DiskSize)"' 2>/dev/null || true)
  [ -n "$spec" ] || return 0   # no profile yet - start flags will apply
  local cpus mem disk
  read -r cpus mem disk <<< "$spec"
  if [ "${cpus:-0}" -lt 4 ] || [ "${mem:-0}" -lt 8192 ] || [ "${disk:-0}" -lt 80 ]; then
    cat >&2 <<EOF
minikube profile '$profile' is ${cpus} CPU / ${mem}Mi / ${disk}Gi, but the
dev overlay needs at least 4 CPU / 8192Mi / 80Gi (sum of pod requests:
2.45 CPU / 6Gi). 'start' does not resize an existing profile, so delete it
and re-run:

  minikube delete
  k8s/bin/dhdev.sh dev-up
EOF
    exit 1
  fi
}

cmd_pull_external() {
  command -v minikube >/dev/null || {
    echo "minikube not found in PATH - install it first: https://minikube.sigs.k8s.io/docs/start/" >&2
    exit 1; }
  command -v docker >/dev/null || {
    echo "docker not found in PATH - install Docker CLI first" >&2
    exit 1; }

  local profile=${MINIKUBE_PROFILE:-minikube}
  if ! minikube -p "$profile" ip >/dev/null 2>&1; then
    echo "minikube profile '$profile' is not running; start it or run '$0 dev-up' first." >&2
    exit 1
  fi

  (
    eval "$(minikube -p "$profile" docker-env)"

    # Make sure we're using Minikube's Docker daemon
    if ! docker info 2>/dev/null | grep -q "minikube"; then
      echo "Error: Not connected to Minikube's Docker daemon!" >&2
      echo "Please run: eval \$(minikube -p $profile docker-env)" >&2
      exit 1
    fi

    echo "==> pulling external images into minikube's Docker daemon..."

    echo "Pulling PostgreSQL image (irods-db, mdr-db, admin-tools-db)..."
    docker pull postgres:17.10-alpine

    echo "Pulling Garage image (garage1, garage2, garage-setup)..."
    docker pull dxflrs/garage:v2.3.0

    echo "Pulling OpenLDAP image (ldap)..."
    docker pull osixia/openldap:1.3.0

    echo "Pulling Nginx image (garage1-s3-tls, garage2-s3-tls)..."
    docker pull nginx:alpine

    echo "Pulling Traefik image (Gateway API controller)..."
    docker pull traefik:v3.7

    echo "All external images have been pulled into Minikube's Docker daemon."
  )
}

bake_k8s_sources() {
  local reg=$1 tag=$2
  shift 2
  local -a only=("$@")

  _wants_bake() {
    local target=$1 s
    [ "${#only[@]}" -eq 0 ] && return 0
    for s in "${only[@]}"; do
      case "$target:$s" in
        epicpid:epicpid|sram-sync:sram-sync|faker:faker|icat:icat|ires-hnas:ires-hnas*) return 0 ;;
      esac
    done
    return 1
  }

  if _wants_bake epicpid; then
    echo "==> baking source into $reg/docker-dev/epicpid:$tag"
    docker build -t "$reg/docker-dev/epicpid:$tag" -f - "$REPO_ROOT/externals/epicpid-microservice" <<EOF
FROM $reg/docker-dev/epicpid:$tag
COPY EPICMicroservice.py /opt/app/EPICMicroservice.py
COPY pid /opt/app/pid
EOF
  fi

  if _wants_bake sram-sync; then
    echo "==> baking source into $reg/docker-dev/sram-sync:$tag"
    docker build -t "$reg/docker-dev/sram-sync:$tag" -f - "$REPO_ROOT/externals/sram-sync" <<EOF
FROM $reg/docker-dev/sram-sync:$tag
COPY *.py /opt/app/
EOF
  fi

  if _wants_bake faker; then
    echo "==> baking source into $reg/docker-dev/faker:$tag"
    docker build -t "$reg/docker-dev/faker:$tag" -f - "$REPO_ROOT/externals/dh-faker" <<EOF
FROM $reg/docker-dev/faker:$tag
COPY *.py *.ini /opt/
COPY assets /opt/assets
EOF
  fi

  local need_irods=0
  _wants_bake icat && need_irods=1
  _wants_bake ires-hnas && need_irods=1
  if [ "$need_irods" -eq 1 ]; then
    local stage
    stage=$(mktemp -d)
    mkdir -p "$stage/rules" "$stage/helpers"
    cp -a "$REPO_ROOT/externals/irods-ruleset/." "$stage/rules/"
    cp -a "$REPO_ROOT/externals/irods-helper-cmd/." "$stage/helpers/"
    rm -rf "$stage/rules/.git" "$stage/helpers/.git"
    local img
    for img in icat ires-hnas; do
      if _wants_bake "$img"; then
        echo "==> baking /rules and /helpers into $reg/docker-dev/$img:$tag"
        docker build -t "$reg/docker-dev/$img:$tag" -f - "$stage" <<EOF
FROM $reg/docker-dev/$img:$tag
COPY --chown=irods:irods rules/ /rules/
COPY --chmod=0755 helpers/ /helpers/
EOF
      fi
    done
    rm -rf "$stage"
  fi
}

cmd_build() {
  local deploy_profile=full
  local -a services=()
  local -a args=("$@")
  local i=0
  while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
      --profile) deploy_profile=${args[$((i+1))]:-}; i=$((i+2)) ;;
      *) services+=("${args[$i]}"); i=$((i+1)) ;;
    esac
  done
  case "$deploy_profile" in
    full|minimal) ;;
    *) echo "unknown profile: '$deploy_profile' (use: full|minimal)" >&2; exit 1 ;;
  esac

  command -v minikube >/dev/null || {
    echo "minikube not found in PATH - install it first: https://minikube.sigs.k8s.io/docs/start/" >&2
    exit 1; }
  command -v docker >/dev/null || {
    echo "docker not found in PATH - install Docker CLI first" >&2
    exit 1; }

  local profile=${MINIKUBE_PROFILE:-minikube}
  if ! minikube -p "$profile" ip >/dev/null 2>&1; then
    echo "minikube profile '$profile' is not running; start it or run '$0 dev-up' first." >&2
    exit 1
  fi

  local -a profile_flags=(--profile full --profile faker)
  if [ "$deploy_profile" = minimal ]; then
    profile_flags=(--profile minimal --profile minimal-after-icat)
  fi

  local secrets_src=$REPO_ROOT/irods.secrets.cfg
  if [ ! -f "$secrets_src" ]; then
    secrets_src=$REPO_ROOT/k8s/overlays/dev/secrets/irods-secrets-cfg.env
  fi

  local tmp_env
  tmp_env=$(mktemp)
  trap 'rm -f "$tmp_env"' RETURN
  cat "$REPO_ROOT/.env" > "$tmp_env"
  printf '\n' >> "$tmp_env"
  cat "$secrets_src" >> "$tmp_env"

  local reg tag
  reg=$(awk -F= '/^ENV_REGISTRY_HOST=/{print $2}' "$REPO_ROOT/.env" | tail -n1 | tr -d '"\r')
  tag=$(awk -F= '/^ENV_TAG=/{print $2}' "$REPO_ROOT/.env" | tail -n1 | tr -d '"\r')
  reg=${ENV_REGISTRY_HOST:-${reg:-registry.prod.dh.unimaas.nl}}
  tag=${ENV_TAG:-${tag:-latest}}

  echo "==> building dev images in minikube Docker daemon (profile: $deploy_profile)"
  (
    export RIT_ENV=${RIT_ENV:-local}
    eval "$(minikube -p "$profile" docker-env)"
    cd "$REPO_ROOT"
    docker compose --env-file "$tmp_env" \
      -f docker-compose.yml -f docker-compose-irods.yml \
      "${profile_flags[@]}" build "${services[@]}"
    bake_k8s_sources "$reg" "$tag" "${services[@]}"
  )
}

cmd_dev_up() {
  local deploy_profile=full
  local do_build=1
  local -a args=("$@")
  local i=0
  while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
      --profile) deploy_profile=${args[$((i+1))]:-}; i=$((i+2)) ;;
      --no-build) do_build=0; i=$((i+1)) ;;
      *) echo "unknown option: ${args[$i]}" >&2; exit 1 ;;
    esac
  done
  case "$deploy_profile" in
    full|minimal) ;;
    *) echo "unknown profile: '$deploy_profile' (use: full|minimal)" >&2; exit 1 ;;
  esac

  command -v minikube >/dev/null || {
    echo "minikube not found in PATH - install it first: https://minikube.sigs.k8s.io/docs/start/" >&2
    exit 1; }
  command -v kubectl  >/dev/null || {
    echo "kubectl not found in PATH - install it first: https://kubernetes.io/docs/tasks/tools/" >&2
    exit 1; }

  echo "==> externals"
  if ! cmd_externals; then
    echo >&2
    echo "externals incomplete - fix the above (SURF credentials!) and re-run." >&2
    exit 1
  fi

  echo "==> minikube"
  check_minikube_size
  local expected_context=${MINIKUBE_PROFILE:-minikube}
  local current_context
  current_context=$(kubectl config current-context 2>/dev/null || true)
  if [ -n "$current_context" ] && [ "$current_context" != "$expected_context" ]; then
    echo "kubectl context is '$current_context', expected '$expected_context'; refusing before starting or modifying a cluster." >&2
    exit 1
  fi
  if minikube ip >/dev/null 2>&1; then
    echo "    already running"
  else
    minikube start --cpus 4 --memory 8192 --disk-size 80
  fi

  current_context=$(kubectl config current-context 2>/dev/null || true)
  if [ "$current_context" != "$expected_context" ]; then
    echo "kubectl context is '$current_context', expected '$expected_context'; refusing to apply dev resources." >&2
    exit 1
  fi

  echo "==> minikube storage provisioner"
  minikube addons enable storage-provisioner
  minikube addons enable default-storageclass
  if ! kubectl get storageclass standard >/dev/null 2>&1; then
    echo "Minikube storage-provisioner addon did not provide StorageClass 'standard'." >&2
    kubectl get storageclass >&2 || true
    exit 1
  fi

  if [ "$do_build" = 1 ]; then
    cmd_pull_external
  fi

  echo "==> traefik (Gateway API)"
  "$SCRIPT_DIR/minikube-traefik.sh"

  if [ "$do_build" = 1 ]; then
    cmd_build --profile "$deploy_profile"
  fi

  echo "==> applying dev overlay (profile: $deploy_profile)"
  local build
  build=$(kubectl kustomize "$REPO_ROOT/k8s/overlays/dev" \
      --load-restrictor LoadRestrictionsNone)
  if [ "$deploy_profile" = minimal ]; then
    # workloads (and their Services) that only the 'full' profile needs
    # carry the label datahub.dh/profile=full
    printf '%s\n' "$build" | kubectl apply -f - -l 'datahub.dh/profile!=full'
    echo "    skipped (full-only workloads):"
    printf '%s\n' "$build" \
      | kubectl apply --dry-run=client -f - -l 'datahub.dh/profile=full' -o name 2>/dev/null \
      | grep -v '^service/' | sed 's/^/      /'
  else
    printf '%s\n' "$build" | kubectl apply -f -
  fi

  echo "==> waiting for PVCs to bind (standard)"
  for _ in $(seq 1 30); do
    pending=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -c Pending || true)
    [ "$pending" = 0 ] && break
    sleep 2
  done
  [ "$pending" = 0 ] || echo "    WARNING: some PVCs still Pending" >&2

  if getent hosts mdr.local.dh.unimaas.nl >/dev/null 2>&1; then
    echo "    /etc/hosts OK"
  else
    cat >&2 <<'EOF'
    WARNING: mdr.local.dh.unimaas.nl does not resolve yet - add the
    /etc/hosts block printed by the traefik step above first.
EOF
  fi

  cat <<'EOF'

dev overlay is applied. First deployment includes the ~30-minute iRODS
bootstrap; watch it with:

  kubectl get pods -A -w
  kubectl -n irods logs icat-0 --all-containers   (when it is up)

Then verify, e.g.:
  curl -s http://mdr.local.dh.unimaas.nl/ | head
  kubectl -n irods exec icat-0 -- iadmin whoami
EOF
}

case "${1:-help}" in
  externals)     cmd_externals ;;
  pull-external) cmd_pull_external ;;
  build)         shift; cmd_build "$@" ;;
  dev-up)        shift; cmd_dev_up "$@" ;;
  help|-h|--help)
    sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) echo "unknown command: $1 (try: externals, pull-external, build, dev-up, help)" >&2; exit 1 ;;
esac
