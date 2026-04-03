#!/bin/sh
# Assign defaultClientScopes to imported Keycloak clients.
#
# Workaround: partialImport ignores defaultClientScopes from client JSONs.
# https://github.com/keycloak/keycloak/issues/16289
# This script reads scope names from .scopes sidecar files and assigns
# them via kcadm.sh. Can be removed when Keycloak fixes the issue.
#
# Scopes not present in the realm are silently skipped (e.g.
# OpenCloudUnique_ID only exists in the LDAP realm variant).
#
# Requires: 00-wait-for-keycloak.sh ran first (kcadm.sh authenticated).
# Usage:    docker exec keycloak /bin/sh /opt/keycloak/bin/11-assign-client-scopes.sh

set -eu

KCADM="/opt/keycloak/bin/kcadm.sh"
REALM="${KC_REALM_NAME:-openCloud}"
CLIENTS_DIR="/opt/keycloak/data/clients"

if [ ! -d "$CLIENTS_DIR" ] || ! ls "$CLIENTS_DIR"/*.scopes >/dev/null 2>&1; then
  echo "[assign-scopes] No .scopes files found — skipping"
  exit 0
fi

# Cache all scope IDs once (avoid repeated API calls)
all_scopes=$($KCADM get client-scopes -r "$REALM" --fields id,name 2>/dev/null || true)

for scopes_file in "$CLIENTS_DIR"/*.scopes; do
  [ -f "$scopes_file" ] || continue
  client_name=$(basename "$scopes_file" .scopes)

  client_id=$($KCADM get clients -r "$REALM" -q "clientId=$client_name" --fields id 2>/dev/null \
    | grep -o '[0-9a-f-]\{36\}' | head -1 || true)
  if [ -z "$client_id" ]; then
    echo "[assign-scopes] $client_name: client not found — skipping"
    continue
  fi

  assigned=""
  skipped=""
  for scope_name in $(tr ',' ' ' < "$scopes_file"); do
    scope_id=$(echo "$all_scopes" | grep -A1 "\"$scope_name\"" | grep '"id"' \
      | grep -o '[0-9a-f-]\{36\}' | head -1)
    if [ -n "$scope_id" ]; then
      $KCADM update "clients/$client_id/default-client-scopes/$scope_id" \
        -r "$REALM" >/dev/null 2>&1 || true
      assigned="$assigned $scope_name"
    else
      skipped="$skipped $scope_name"
    fi
  done
  echo "[assign-scopes] $client_name:$assigned${skipped:+ (skipped:$skipped)}"
done

echo "[assign-scopes] Done"
