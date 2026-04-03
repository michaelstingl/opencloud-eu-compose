#!/bin/sh
# Import Keycloak client definitions from /opt/keycloak/data/clients/*.json
# via kcadm.sh partialImport. Existing clients are skipped (idempotent).
#
# Requires: 00-wait-for-keycloak.sh ran first (kcadm.sh authenticated).
# Usage:    docker exec keycloak /bin/sh /opt/keycloak/bin/10-import-clients.sh

set -eu

KCADM="/opt/keycloak/bin/kcadm.sh"
REALM="${KC_REALM_NAME:-openCloud}"
CLIENTS_DIR="/opt/keycloak/data/clients"
OC_URL="https://${OC_DOMAIN:-cloud.opencloud.test}"

if [ ! -d "$CLIENTS_DIR" ] || ! ls "$CLIENTS_DIR"/*.json >/dev/null 2>&1; then
  echo "[import-clients] No client files found — skipping"
  exit 0
fi

for client_file in "$CLIENTS_DIR"/*.json; do
  [ -f "$client_file" ] || continue
  client_name=$(basename "$client_file" .json)
  tmp_file=$(mktemp)

  # Keycloak's --import-realm resolves {{VAR}} from env vars.
  # partialImport does not — we replicate this for {{OC_URL}}.
  sed "s|{{OC_URL}}|${OC_URL}|g" "$client_file" > "$tmp_file"

  # Wrap in partialImport payload (SKIP existing)
  tmp_payload=$(mktemp)
  printf '{"ifResourceExists":"SKIP","clients":[' > "$tmp_payload"
  cat "$tmp_file" >> "$tmp_payload"
  printf ']}' >> "$tmp_payload"

  if $KCADM create partialImport -r "$REALM" -f "$tmp_payload" >/dev/null 2>&1; then
    echo "[import-clients] $client_name"
  else
    echo "[import-clients] $client_name — failed" >&2
  fi

  rm -f "$tmp_file" "$tmp_payload"
done

echo "[import-clients] Done"
