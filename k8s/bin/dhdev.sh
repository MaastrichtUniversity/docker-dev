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
# Usage:  k8s/bin/dhdev.sh <externals|dev-up|help>
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

cmd_dev_up() {
  command -v minikube >/dev/null || { echo "minikube not found in PATH" >&2; exit 1; }
  command -v kubectl  >/dev/null || { echo "kubectl not found in PATH" >&2; exit 1; }

  echo "==> externals"
  if ! cmd_externals; then
    echo >&2
    echo "externals incomplete - fix the above (SURF credentials!) and re-run." >&2
    exit 1
  fi

  echo "==> minikube"
  if minikube ip >/dev/null 2>&1; then
    echo "    already running"
  else
    # flags only apply when the profile is created; if your profile was
    # created smaller, 'minikube delete' first.
    minikube start --cpus 4 --memory 8192 --disk-size 80
  fi

  echo "==> traefik (Gateway API)"
  "$SCRIPT_DIR/minikube-traefik.sh"

  echo "==> applying dev overlay"
  kubectl kustomize "$REPO_ROOT/k8s/overlays/dev" \
      --load-restrictor LoadRestrictionsNone | kubectl apply -f -

  echo "==> waiting for PVCs to bind (local-path)"
  for _ in $(seq 1 30); do
    pending=$(kubectl get pvc -A --no-headers 2>/dev/null | grep -c Pending || true)
    [ "$pending" = 0 ] && break
    sleep 2
  done
  [ "$pending" = 0 ] || echo "    WARNING: some PVCs still Pending" >&2

  if getent hosts mdr.dev.dh.unimaas.nl >/dev/null 2>&1; then
    echo "    /etc/hosts OK"
  else
    cat >&2 <<'EOF'
    WARNING: mdr.dev.dh.unimaas.nl does not resolve yet - add the
    /etc/hosts block printed by the traefik step above first.
EOF
  fi

  cat <<'EOF'

dev overlay is applied. First deployment includes the ~30-minute iRODS
bootstrap; watch it with:

  kubectl get pods -A -w
  kubectl -n irods logs icat-0 --all-containers   (when it is up)

Then verify, e.g.:
  curl -s http://mdr.dev.dh.unimaas.nl/ | head
  kubectl -n irods exec icat-0 -- iadmin whoami
EOF
}

case "${1:-help}" in
  externals) cmd_externals ;;
  dev-up)    cmd_dev_up ;;
  help|-h|--help)
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *) echo "unknown command: $1 (try: externals, dev-up, help)" >&2; exit 1 ;;
esac
