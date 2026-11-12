#!/bin/bash
set -euo pipefail

state_file=/var/run/dh_import_state
if [[ -f "$state_file" && "$(< "$state_file")" == failed ]]; then
  echo FAILED
  exit 2
fi
if [[ -f "$state_file" && "$(< "$state_file")" == completed ]] && \
    curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 \
      http://localhost:8080/auth/realms/django/.well-known/openid-configuration > /dev/null 2>&1; then
  echo READY
else
  echo "NOT READY"
  exit 1
fi
