#!/bin/bash
set -euo pipefail
umask 077

state_file=/var/run/dh_import_state
work_dir=""
finish() {
  local status=$?
  [[ -z "$work_dir" ]] || rm -rf "$work_dir"
  if (( status != 0 )); then
    echo failed > "$state_file"
    echo "ERROR: Keycloak initialization failed (exit $status)." >&2
  fi
}
trap finish EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

echo starting > "$state_file"
echo "Starting Keycloak initialization"
work_dir=$(mktemp -d)
base_url=http://localhost:8080/auth
deadline=$((SECONDS + 180))
until curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 "$base_url/realms/master" > /dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "ERROR: Keycloak HTTP endpoint did not become ready within 180 seconds." >&2
    exit 1
  fi
  sleep 1
done

echo "Login"
curl -fsS --noproxy '*' --connect-timeout 2 --max-time 30 \
  --data-urlencode grant_type=password --data-urlencode client_id=admin-cli \
  --data-urlencode "username=$KEYCLOAK_USER" --data-urlencode "password=$KEYCLOAK_PASSWORD" \
  "$base_url/realms/master/protocol/openid-connect/token" > "$work_dir/token.json"
token=$(jq -er '.access_token' "$work_dir/token.json")
kc() {
  local path=$1
  shift
  curl -fsS --noproxy '*' --connect-timeout 2 --max-time 30 \
    -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
    "$base_url/admin/$path" "$@"
}

kc realms/master -X PUT --data '{"sslRequired":"NONE"}'
kc realms > "$work_dir/realms.json"
if ! jq -e 'any(.[]; .realm == "django")' "$work_dir/realms.json" > /dev/null; then
  echo "Import Django realm"
  jq --arg environment "$RIT_ENV" --arg password "$LDAP_ADMIN_PASSWORD" '
    walk(if type == "string" then gsub("RIT_ENV"; $environment) else . end)
    | (.components["org.keycloak.storage.UserStorageProvider"][]
       | select(.providerId == "ldap") | .config.bindCredential) = [$password]
  ' /tmp/realm-export.json > "$work_dir/realm.json"
  kc realms -X POST --data-binary "@$work_dir/realm.json"
fi

echo "Full Sync LDAP"
kc 'realms/django/user-storage/10d55377-d139-4865-bd3e-1375ea079925/sync?action=triggerFullSync' \
  -X POST > "$work_dir/sync.json"
jq -e '(.failed // 0) == 0' "$work_dir/sync.json" > /dev/null

# Keep the default here so existing Jenkins substitution remains compatible.
fixture_password=${DEMO_KEYCLOAK_PASSWORD:-foobar}
jq -n --arg value "$fixture_password" '{type: "password", value: $value, temporary: false}' \
  > "$work_dir/password.json"
# With LDAP import disabled, an explicit wildcard query is needed to enumerate users.
kc 'realms/django/users?username=*&max=1000' > "$work_dir/users.json"
jq -r --slurpfile users "$work_dir/users.json" '
  .[] | .userName as $name
  | [$users[0][] | select(.username == $name) | .id]
  | if length != 1 then error("Expected exactly one LDAP user: " + $name)
    else .[0] | @uri end
' /tmp/users.json > "$work_dir/user_ids"

echo "Setting fixture user passwords"
while IFS= read -r user_id; do
  kc "realms/django/users/$user_id/reset-password" -X PUT --data-binary "@$work_dir/password.json"
done < "$work_dir/user_ids"

echo "Keycloak initialization completed"
echo completed > "$state_file"
