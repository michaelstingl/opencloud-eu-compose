#!/bin/sh
# Wait for Keycloak to accept admin credentials via kcadm.sh.
# Exits 0 when ready, 1 on timeout.
#
# Usage: docker exec keycloak /bin/sh /opt/keycloak/bin/00-wait-for-keycloak.sh

KCADM="/opt/keycloak/bin/kcadm.sh"
MAX_WAIT="${KC_MAX_WAIT:-120}"

echo "[wait-for-kc] Waiting for Keycloak..."
elapsed=0
while [ $elapsed -lt $MAX_WAIT ]; do
  if $KCADM config credentials \
      --server http://localhost:8080 --realm master \
      --user "${KEYCLOAK_ADMIN:-kcadmin}" \
      --password "${KEYCLOAK_ADMIN_PASSWORD:-admin}" >/dev/null 2>&1; then
    echo "[wait-for-kc] Ready (${elapsed}s)"
    exit 0
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done

echo "[wait-for-kc] Not ready after ${MAX_WAIT}s"
exit 1
