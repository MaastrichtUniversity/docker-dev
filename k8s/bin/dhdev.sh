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
#                                (minikube-traefik.sh), apply of the dev overlay
#                                (with the real ATLASSIAN_API_* credentials
#                                from irods.secrets.cfg injected into the dev
#                                secrets - local, gitignored), readiness checks.
#                                Idempotent - re-run
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
#
# Dependencies: minikube and kubectl are checked on every run and installed
# automatically (user-local, into ~/.local/bin, no sudo) when missing; set
# DHDEV_NO_INSTALL=1 for check-only. docker and git are check-only.
# `minikube start` passes the corporate proxy to the node container via
# --docker-env with a no_proxy covering the cluster-local ranges (see the
# start block in cmd_dev_up and the Troubleshooting row in k8s/README.md).
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
EXTERNALS_DIR=$REPO_ROOT/externals
SURF_DIR=$EXTERNALS_DIR/epicpid-microservice/credentials
SURF_FILES="305_21_T12996_USER01_UM_privkey.pem
305_21_T12996_USER01_UM_certificate_only.pem"

# --- dependency checks / installs --------------------------------------------
# dhdev does not install system packages. What it CAN install without root
# are the minikube and kubectl single binaries (into $DHDEV_BIN_DIR, default
# ~/.local/bin). Docker and git are check-only: they need a package manager
# / service setup that must not run unattended.
# Set DHDEV_NO_INSTALL=1 for check-only behavior.

_http_get() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
  else echo "    $0: need curl or wget to download $1" >&2; return 1; fi
}

_install_tool() {
  local tool="$1" dest="${2:-$HOME/.local/bin}" os arch ver url
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) echo "    $0: unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac
  case "$os" in linux|darwin) ;; *) echo "    $0: unsupported OS: $os" >&2; return 1 ;; esac
  mkdir -p "$dest" || return 1
  case "$tool" in
    minikube)
      ver=$(_http_get "https://api.github.com/repos/kubernetes/minikube/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":\s*"v[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
      [ -n "$ver" ] || { echo "    $0: could not determine the latest minikube release" >&2; return 1; }
      url="https://github.com/kubernetes/minikube/releases/download/${ver}/minikube-${os}-${arch}.tar.gz"
      # the binary sits top-level in older releases and under out/ in newer
      # ones (e.g. out/minikube-linux-amd64) - extract and find it
      local tmpd bin
      tmpd=$(mktemp -d) || return 1
      _http_get "$url" | tar -xz -C "$tmpd" || { rm -rf "$tmpd"; return 1; }
      bin=$(find "$tmpd" -type f -name 'minikube*' ! -name '*.sha256' | head -1)
      [ -n "$bin" ] || { echo "    $0: minikube binary not found in the archive" >&2; rm -rf "$tmpd"; return 1; }
      mv "$bin" "$dest/minikube" && rm -rf "$tmpd"
      ;;
    kubectl)
      # dl.k8s.io/stable.txt is gone; the latest tag comes from the GitHub release
      ver=$(_http_get "https://api.github.com/repos/kubernetes/kubernetes/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":\s*"v[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
      [ -n "$ver" ] || { echo "    $0: could not determine the latest kubernetes release" >&2; return 1; }
      url="https://dl.k8s.io/${ver}/bin/${os}/${arch}/kubectl"
      _http_get "$url" > "$dest/kubectl" || return 1
      ;;
    *) echo "    $0: no auto-install for '$tool'" >&2; return 1 ;;
  esac
  chmod +x "$dest/$tool" || return 1
  # version-check without a cluster: minikube 'version' is standalone;
  # kubectl needs --client (plain 'version' or '--version' fail without one)
  local ver_cmd="$dest/$tool version"
  [ "$tool" = kubectl ] && ver_cmd="$dest/$tool version --client"
  if ! $ver_cmd >/dev/null 2>&1; then
    echo "    $0: installed $tool binary failed its version check - removing it" >&2
    rm -f "$dest/$tool"; return 1
  fi
  echo "    installed $tool $ver -> $dest"
}

# ensure_deps TOOL...: verify the given tools are available. minikube and
# kubectl are auto-installed (user-local, no sudo) when missing unless
# DHDEV_NO_INSTALL=1; everything else is check-only with a clear message.
ensure_deps() {
  local dest="${DHDEV_BIN_DIR:-$HOME/.local/bin}" tool ok=0
  for tool in "$@"; do
    if command -v "$tool" >/dev/null 2>&1; then continue; fi
    case "$tool" in
      minikube|kubectl)
        if [ "${DHDEV_NO_INSTALL:-0}" = "1" ]; then
          echo "    MISSING: $tool (auto-install disabled by DHDEV_NO_INSTALL=1)" >&2
          ok=1; continue
        fi
        echo "==> $tool not found - installing to $dest (no sudo needed)"
        _install_tool "$tool" "$dest" || ok=1
        ;;
      *)
        case "$tool" in
          docker) echo "    MISSING: docker - install Docker Engine/CLI for your OS first (no auto-install)" >&2 ;;
          git)    echo "    MISSING: git - install it with your package manager first (no auto-install)" >&2 ;;
          *)      echo "    MISSING: $tool - install it first (no auto-install)" >&2 ;;
        esac
        ok=1 ;;
    esac
  done
  if [ "$ok" = 1 ]; then
    echo "    Fix the missing tools above and re-run '$(basename "$0").'" >&2
    return 1
  fi
  # make this run see the freshly installed binaries
  if [ -d "$dest" ] && [[ ":$PATH:" != *":$dest:"* ]]; then
    export PATH="$dest:$PATH"
    echo "    note: $dest was added to PATH for this run; add it to your shell profile to use the tools outside this script"
  fi
  return 0
}


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
  # minikube >= 1.38: {invalid:[], valid:[{Name, Config:{CPUs, Memory, DiskSize(MB)}, ...}]}
  spec=$(minikube profile list -o json 2>/dev/null \
    | jq -r --arg p "$profile" '.valid[] | select(.Name==$p) | "\(.Config.CPUs) \(.Config.Memory) \(.Config.DiskSize)"' 2>/dev/null || true)
  [ -n "$spec" ] || return 0   # no profile yet - start flags will apply
  local cpus mem disk
  read -r cpus mem disk <<< "$spec"
  if [ "${cpus:-0}" -lt 4 ] || [ "${mem:-0}" -lt 8192 ] || [ "${disk:-0}" -lt 81920 ]; then
    cat >&2 <<EOF
minikube profile '$profile' is ${cpus} CPU / ${mem}Mi / $(( ${disk:-0} / 1024 ))Gi, but the
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
  ensure_deps minikube docker || exit 1

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
        epicpid:epicpid|sram-sync:sram-sync|faker:faker|mdr:mdr|admin-tools-backend:admin-tools-backend|davrods:davrods|davrods-upload:davrods-upload|icat:icat|ires-hnas:ires-hnas*) return 0 ;;
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
    # irods-rule-wrapper@2026.1 was deleted upstream, so the compose build
    # (locally patched requirements.txt) no longer installs it - install it
    # here from the local externals checkout instead.
    local sram_stage
    sram_stage=$(mktemp -d)
    mkdir -p "$sram_stage"
    cp -a "$REPO_ROOT/externals/sram-sync" "$sram_stage/sram-sync"
    cp -a "$REPO_ROOT/externals/irods-rule-wrapper" "$sram_stage/irods-rule-wrapper"
    rm -rf "$sram_stage/irods-rule-wrapper/.git"
    docker build -t "$reg/docker-dev/sram-sync:$tag" -f - "$sram_stage" <<EOF
FROM $reg/docker-dev/sram-sync:$tag
COPY sram-sync/*.py /opt/app/
COPY irods-rule-wrapper/ /tmp/irods-rule-wrapper/
RUN pip3 install --no-cache-dir /tmp/irods-rule-wrapper && rm -rf /tmp/irods-rule-wrapper
EOF
    rm -rf "$sram_stage"
  fi

  if _wants_bake faker; then
    echo "==> baking source into $reg/docker-dev/faker:$tag"
    docker build -t "$reg/docker-dev/faker:$tag" -f - "$REPO_ROOT/externals/dh-faker" <<EOF
FROM $reg/docker-dev/faker:$tag
COPY *.py *.ini /opt/
COPY assets /opt/assets
EOF
  fi

  if _wants_bake mdr; then
    echo "==> baking irods-rule-wrapper and dhpythonirodsutils into $reg/docker-dev/mdr:$tag"
    local mdr_stage
    mdr_stage=$(mktemp -d)
    mkdir -p "$mdr_stage/irods-rule-wrapper" "$mdr_stage/dhpythonirodsutils"
    cp -a "$REPO_ROOT/externals/irods-rule-wrapper/." "$mdr_stage/irods-rule-wrapper/"
    cp -a "$REPO_ROOT/externals/dh-python-irods-utils/dhpythonirodsutils/." "$mdr_stage/dhpythonirodsutils/"
    rm -rf "$mdr_stage/irods-rule-wrapper/.git"
    docker build -t "$reg/docker-dev/mdr:$tag" -f - "$mdr_stage" <<EOF
FROM $reg/docker-dev/mdr:$tag
COPY irods-rule-wrapper/ /opt/src/irods-rule-wrapper/
# irods-rule-wrapper@2026.1 was deleted upstream, so the compose build (locally
# patched requirements.txt) no longer pip-installs it - install it from the
# local source here (pulls its pinned git deps from GitHub too).
RUN pip install --no-cache-dir /opt/src/irods-rule-wrapper
COPY dhpythonirodsutils/ /usr/local/lib/python3.11/site-packages/dhpythonirodsutils/
EOF
    rm -rf "$mdr_stage"
  fi

  local ca_file=$REPO_ROOT/irods/k8s-ssl-certs/ca.pem
  if [ -f "$ca_file" ]; then
    local client_img
    for client_img in sram-sync faker mdr admin-tools-backend davrods davrods-upload; do
      if _wants_bake "$client_img"; then
        echo "==> baking k8s iRODS CA into $reg/docker-dev/$client_img:$tag"
        docker build -t "$reg/docker-dev/$client_img:$tag" -f - "$REPO_ROOT/irods/k8s-ssl-certs" <<EOF
FROM $reg/docker-dev/$client_img:$tag
USER root
COPY ca.pem /usr/local/share/ca-certificates/k8s_irods_ca.crt
RUN update-ca-certificates
EOF
      fi
    done
  fi

  local need_irods=0
  _wants_bake icat && need_irods=1
  _wants_bake ires-hnas && need_irods=1
  if [ "$need_irods" -eq 1 ]; then
    local stage
    stage=$(mktemp -d)
    mkdir -p "$stage/rules" "$stage/helpers" "$stage/dh-python-irods-utils"
    cp -a "$REPO_ROOT/externals/irods-ruleset/." "$stage/rules/"
    cp -a "$REPO_ROOT/externals/irods-helper-cmd/." "$stage/helpers/"
    cp -a "$REPO_ROOT/externals/dh-python-irods-utils/." "$stage/dh-python-irods-utils/"
    rm -rf "$stage/rules/.git" "$stage/helpers/.git" "$stage/dh-python-irods-utils/.git"
    python3 - "$stage/rules/setup.py" "$stage/rules/Makefile" <<'PY'
import re, sys
setup_p, make_p = sys.argv[1], sys.argv[2]
s = open(setup_p).read()
s = re.sub(r'"dh-python-irods-utils[^"]*"', '"dh-python-irods-utils"', s)
open(setup_p, "w").write(s)

m = open(make_p).read()
new_target = (
    "pip-install:\n"
    "\techo \"from datahubirodsruleset import *\\n\" > /etc/irods/core.py\n"
    "\tset -e; tmpdir=\"$$(mktemp -d /tmp/datahub-irods-ruleset.XXXXXX)\"; \\\n"
    "\ttrap 'rm -rf \"$$tmpdir\"' EXIT; \\\n"
    "\tcp -a . \"$$tmpdir/src\"; \\\n"
    "\trm -rf \"$$tmpdir/src/build\" \"$$tmpdir/src/datahub_irods_ruleset.egg-info\"; \\\n"
    "\tpip3 install --user --no-index --find-links=/opt/rules-wheels --no-deps --force-reinstall /opt/rules-wheels/dh_python_irods_utils-*.whl $(PIP_BREAK_FLAG) --no-warn-script-location; \\\n"
    "\tpip3 install --user --no-build-isolation --no-index --find-links=/opt/rules-wheels \"$$tmpdir/src\" $(PIP_BREAK_FLAG) --no-warn-script-location\n"
)
m = re.sub(r"pip-install:.*?(?=\n\.PHONY:|\Z)", lambda _: new_target, m, flags=re.S)
open(make_p, "w").write(m)
PY
    local img
    for img in icat ires-hnas; do
      if _wants_bake "$img"; then
        echo "==> baking /rules, /helpers, and offline /opt/rules-wheels into $reg/docker-dev/$img:$tag"
        docker build -t "$reg/docker-dev/$img:$tag" -f - "$stage" <<EOF
FROM $reg/docker-dev/$img:$tag
COPY --chown=irods:irods rules/ /rules/
COPY --chmod=0755 helpers/ /helpers/
COPY dh-python-irods-utils/ /tmp/dh-python-irods-utils/
RUN pip3 wheel --wheel-dir=/opt/rules-wheels setuptools wheel /tmp/dh-python-irods-utils /rules \
 && rm -rf /tmp/dh-python-irods-utils
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

  ensure_deps minikube docker || exit 1
  if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose (v2 plugin) not found - install it first: https://docs.docker.com/compose/install/" >&2
    exit 1
  fi

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
  trap 'rm -f "${tmp_env:-}"' RETURN
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

# Stages a copy of the dev overlay (generator file references stay valid via
# repo symlinks). inject_atlassian_secrets replaces the ATLASSIAN_API_*
# values in the staged secret env files with the real ones from
# irods.secrets.cfg (local, gitignored via *.secrets.cfg); the committed
# files keep their placeholders, so real credentials never land in git.
# build_dev_overlay prints the kustomize build on stdout and sets
# dev_overlay_injected=1 (in the caller's shell) if anything was replaced.
stage_dev_overlay() {
  # Sets STAGE_DIR in the caller's shell. No cleanup trap here: a RETURN
  # trap fires at the return of *every* function it is active in, which
  # would delete the stage before build_dev_overlay is done with it.
  local t
  STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dhdev-overlay.XXXXXX")
  mkdir -p "$STAGE_DIR/k8s/overlays"
  cp -a "$REPO_ROOT/k8s/overlays/dev" "$STAGE_DIR/k8s/overlays/dev"
  # The dev kustomization resolves ../../base to $STAGE_DIR/k8s/base, and
  # base/ generator files resolve ../../ (resp. ../../../ from the overlay)
  # to the repo root - symlink the trees they read.
  ln -s "$REPO_ROOT/k8s/base" "$STAGE_DIR/k8s/base"
  for t in externals irods keycloak; do
    ln -s "$REPO_ROOT/$t" "$STAGE_DIR/$t"
  done
}

# Runs in the caller's shell so the dev_overlay_injected flag survives.
inject_atlassian_secrets() {
  local overlay_dir="$1"
  local src k v file
  dev_overlay_injected=0
  src=$REPO_ROOT/irods.secrets.cfg
  if [ ! -f "$src" ]; then
    echo "WARNING: irods.secrets.cfg not found at the repo root - building with the committed placeholder secrets." >&2
    return 0
  fi
  for k in ATLASSIAN_API_USERNAME ATLASSIAN_API_KEY; do
    v=$(grep -E "^${k}=" "$src" | head -1 | cut -d= -f2- | tr -d '\r')
    if [ -z "$v" ]; then
      echo "WARNING: $k missing from irods.secrets.cfg - keeping committed placeholder." >&2
      continue
    fi
    for file in "$overlay_dir"/secrets/*.env; do
      grep -qE "^${k}=" "$file" || continue
      awk -v k="$k" -v v="$v" 'index($0, k "=") == 1 { print k "=" v; next } { print }' \
        "$file" > "$file.tmp" && mv "$file.tmp" "$file"
      echo "    injected real $k into $(basename "$file")" >&2
      dev_overlay_injected=1
    done
  done
}

# Writes the kustomize build of the staged dev overlay to $1 (a file the
# caller passes in). Runs in the main shell so the dev_overlay_injected
# flag set by inject_atlassian_secrets survives for the caller.
build_dev_overlay() {
  local out_file="$1" rc=0
  stage_dev_overlay
  inject_atlassian_secrets "$STAGE_DIR/k8s/overlays/dev"
  kubectl kustomize "$STAGE_DIR/k8s/overlays/dev" --load-restrictor LoadRestrictionsNone > "$out_file" || rc=$?
  rm -rf "$STAGE_DIR"
  STAGE_DIR=
  return "$rc"
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

  ensure_deps minikube kubectl docker git || exit 1

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
    # Guarantee the 'minikube' docker network is on 192.168.49.0/24 BEFORE
    # start: minikube reuses an existing 'minikube' network. If that network
    # was created by docker's pool allocator on a different subnet (e.g.
    # 192.168.58.0/24, when the .49 subnet was transiently unavailable), the
    # node gets an IP outside the corporate no_proxy lists and the kubelet's
    # apiserver traffic dies in the proxy (it answers '403 Forbidden').
    # Only touch the network of OUR profile; leave 'minikube-<other>' alone.
    local minikube_net_subnet
    minikube_net_subnet=$(docker network inspect minikube \
      --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || true)
    case "$minikube_net_subnet" in
      192.168.49.0/24) : ;;
      "") docker network create --subnet 192.168.49.0/24 minikube >/dev/null 2>&1 \
          || echo "    WARNING: could not pre-create docker network minikube@192.168.49.0/24" >&2 ;;
      *)  echo "    docker network 'minikube' is on $minikube_net_subnet (want 192.168.49.0/24) - recreating it"
          docker network rm minikube >/dev/null 2>&1 \
            || { echo "    WARNING: network 'minikube' is in use - start may land on the wrong subnet" >&2; }
          docker network create --subnet 192.168.49.0/24 minikube >/dev/null 2>&1 \
            || echo "    ERROR: could not create docker network minikube@192.168.49.0/24 (subnet in use by another network? - check: docker network ls)" >&2
          ;;
    esac
    # Corporate proxy (UM): the node container inherits the docker daemon's
    # proxy env, whose NO_PROXY lacks the cluster-local ranges - so the
    # kubelet routes its apiserver traffic (192.168.49.2:6443) through the
    # proxy, never registers the node, and kubeadm init dies with
    # 'nodes "minikube" not found' (GUEST_START). --docker-env sets the node
    # container env explicitly: 192.168.49.0/24 = node/LB range,
    # 10.96.0.0/12 = service CIDR, 10.244.0.0/16 = pod CIDR, plus the
    # corporate bypass domains. NOTE: --docker-env only applies at node
    # creation - if these values change, run `minikube delete` first.
    minikube start --cpus 4 --memory 8192 --disk-size 80g --driver=docker \
      --docker-env http_proxy="http://proxy.unimaas.nl:3128/" \
      --docker-env https_proxy="http://proxy.unimaas.nl:3128/" \
      --docker-env no_proxy="localhost,127.0.0.1,192.168.49.0/24,10.96.0.0/12,10.244.0.0/16,.dh.local,.unimaas.nl,.datahubmaastricht.nl,epic-pid.storage.surfsara.nl"
  fi

  # Hard fail if the node ended up on a different subnet - the metallb pool,
  # /etc/hosts LB IP and the no_proxy lists all assume 192.168.49.x.
  local node_ip
  node_ip=$(minikube ip 2>/dev/null || true)
  case "$node_ip" in
    192.168.49.*) ;;
    *) echo "ERROR: minikube node IP is '$node_ip' (expected 192.168.49.x)." >&2
       echo "      The 'minikube' docker network is likely on another subnet. Fix:" >&2
       echo "      minikube delete && docker network rm minikube" >&2
       echo "      docker network create --subnet 192.168.49.0/24 minikube && dev-up" >&2
       exit 1 ;;
  esac

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
  local build_manifest build
  build_manifest=$(mktemp "${TMPDIR:-/tmp}/dhdev-manifest.XXXXXX")
  trap 'rm -f "${tmp_env:-}" "${build_manifest:-}"' RETURN
  build_dev_overlay "$build_manifest"
  build=$(<"$build_manifest")
  rm -f "$build_manifest"
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

  if [ "${dev_overlay_injected:-0}" = 1 ]; then
    # env is snapshotted into pods at start - roll the consumers so the
    # injected secrets take effect.
    echo "==> rolling workloads that consume the injected secrets"
    kubectl -n internal rollout restart deploy/admin-tools-backend
    kubectl -n public rollout restart deploy/help-center-backend
    kubectl -n external rollout restart deploy/mdr
    cat <<'NOTE'
    NOTE: the irods-secrets-cfg secret also feeds icat/ires-hnas. Do NOT
    restart them mid-bootstrap; once iRODS is up:
      kubectl -n irods rollout restart statefulset/icat statefulset/ires-hnas-um statefulset/ires-hnas-azm
NOTE
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
