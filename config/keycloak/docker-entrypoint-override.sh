#!/bin/bash
# print env variables for trace/debug log levels
log_level=$(printf '%s' "$KC_LOG_LEVEL" | tr '[:upper:]' '[:lower:]')
case "$log_level" in trace|debug) printenv ;; *) ;; esac

# replace openCloud domain and LDAP password in keycloak realm import
mkdir -p /opt/keycloak/data/import
sed -e "s/cloud.opencloud.test/${OC_DOMAIN}/g" -e "s/ldap-admin-password/${LDAP_ADMIN_PASSWORD:-admin}/g" /opt/keycloak/data/import-dist/openCloud-realm.json > /opt/keycloak/data/import/openCloud-realm.json

# Post-start pipeline (background): import modular client definitions.
# Each step is standalone and can be run manually for debugging:
#   docker exec keycloak /bin/sh /opt/keycloak/bin/10-import-clients.sh
(
  if ! /bin/sh /opt/keycloak/bin/00-wait-for-keycloak.sh; then
    echo "[post-start] Keycloak not ready — skipping client import"
    exit 0
  fi
  /bin/sh /opt/keycloak/bin/10-import-clients.sh
  /bin/sh /opt/keycloak/bin/11-assign-client-scopes.sh
  echo "[post-start] Done"
) &

# run original docker-entrypoint
/opt/keycloak/bin/kc.sh "$@"
