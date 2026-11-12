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
#   k8s/bin/dhdev.sh dev-up      spin up / refresh the dev overlay on
#                                local minikube: externals check, minikube
#                                (4 CPU / 8Gi / 80Gi), loadbalancer addon,
#                                Traefik with Gateway API (minikube-
#                                traefik.sh), apply of the dev overlay,
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
# Usage:  k8s/bin/dhdev.sh <externals|dev-up [--profile full|minimal]|help>
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

cmd_dev_up() {
  local deploy_profile=full
  local -a args=("$@")
  local i=0
  while [ "$i" -lt "${#args[@]}" ]; do
    case "${args[$i]}" in
      --profile) deploy_profile=${args[$((i+1))]:-}; i=$((i+2)) ;;
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

  echo "==> traefik (Gateway API)"
  "$SCRIPT_DIR/minikube-traefik.sh"

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
  externals) cmd_externals ;;
  dev-up)    shift; cmd_dev_up "$@" ;;
  help|-h|--help)
    sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) echo "unknown command: $1 (try: externals, dev-up, help)" >&2; exit 1 ;;
esac
