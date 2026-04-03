#!/bin/bash
# validate-modular-clients.sh — Prove modular client import matches monolith.
#
# Starts two throwaway Keycloak containers per realm variant:
#   A) Original monolith realm (clients embedded in realm JSON)
#   B) Slim realm + modular client import via entrypoint pipeline
#
# Compares: clients, client-scopes, roles, groups, realm settings.
# Tests both realm variants (LDAP and autoprovisioning).
#
# Usage:   bash config/keycloak/validate-modular-clients.sh
# Prereqs: docker, jq
#
# Exit 0 = identical, exit 1 = differences found.

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
KC_IMAGE="quay.io/keycloak/keycloak:26.5.6"
REALM="openCloud"
WORK=$(mktemp -d)
RAW_BASE="https://raw.githubusercontent.com/opencloud-eu/opencloud-compose/main/config/keycloak"
RESULT=0

trap 'docker rm -f kc-validate-a kc-validate-b 2>/dev/null; rm -rf "$WORK"' EXIT

echo "=== Modular Keycloak Realm Validation ==="
echo "  Keycloak: $KC_IMAGE"
echo "  Work dir: $WORK"

# ── Helpers ──────────────────────────────────────────────────────────

wait_for_kc() {
  local name="$1" max=60
  echo -n "  Waiting for $name"
  for i in $(seq 1 $max); do
    if docker exec "$name" /opt/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:8080 --realm master \
        --user admin --password admin 2>/dev/null; then
      echo " ready (${i}s)"
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo " TIMEOUT"; return 1
}

wait_for_pipeline() {
  local name="$1" max=90
  echo -n "  Waiting for post-start pipeline"
  for i in $(seq 1 $max); do
    if docker logs "$name" 2>&1 | grep -q "\[post-start\] Done"; then
      echo " done (${i}s)"
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo " TIMEOUT"; return 1
}

export_all() {
  local name="$1" prefix="$2"
  local KCADM="docker exec $name /opt/keycloak/bin/kcadm.sh"
  docker exec "$name" /opt/keycloak/bin/kcadm.sh config credentials \
    --server http://localhost:8080 --realm master --user admin --password admin >/dev/null 2>&1
  $KCADM get clients -r "$REALM"       > "$prefix-clients.json"
  $KCADM get client-scopes -r "$REALM" > "$prefix-client-scopes.json"
  $KCADM get roles -r "$REALM"         > "$prefix-roles.json"
  $KCADM get groups -r "$REALM"        > "$prefix-groups.json"
  $KCADM get "realms/$REALM"           > "$prefix-realm.json"
}

# Normalize JSON: remove volatile fields, sort keys and arrays
normalize() {
  jq 'walk(
    if type == "object" then del(.id, .containerId, .secret, .["client.secret.creation.time"])
    elif type == "array" then sort_by(tostring)
    else . end
  )' "$1" | jq -S .
}

# Compare two JSON arrays by a key field (clientId or name)
compare_by_key() {
  local orig="$1" mod="$2" label="$3" key="$4"
  local a b
  a=$(normalize "$orig")
  b=$(normalize "$mod")

  local orig_keys mod_keys
  orig_keys=$(echo "$a" | jq -r ".[].$key // empty" | sort)
  mod_keys=$(echo "$b" | jq -r ".[].$key // empty" | sort)

  local all_ok=true
  local new_items=""

  # Items only in modular (new)
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if ! echo "$orig_keys" | grep -qx "$name"; then
      new_items="$new_items $name"
    fi
  done <<< "$mod_keys"

  # Compare each original item
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    if ! echo "$mod_keys" | grep -qx "$name"; then
      echo "  MISSING  $name"
      all_ok=false
      continue
    fi

    local orig_item mod_item
    orig_item=$(echo "$a" | jq -c --arg n "$name" "[.[] | select(.$key == \$n)][0]" | jq -S .)
    mod_item=$(echo "$b" | jq -c --arg n "$name" "[.[] | select(.$key == \$n)][0]" | jq -S .)

    if [ "$orig_item" = "$mod_item" ]; then
      echo "  OK       $name"
    else
      echo "  DIFFER   $name"
      diff <(echo "$orig_item" | jq .) <(echo "$mod_item" | jq .) | head -20 | sed 's/^/           /'
      all_ok=false
    fi
  done <<< "$orig_keys"

  for name in $new_items; do
    echo "  NEW      $name"
  done

  local count
  count=$(echo "$orig_keys" | grep -c . || true)
  local new_count
  new_count=$(echo "$new_items" | wc -w | tr -d ' ')

  echo ""
  if $all_ok; then
    local extra=""
    [ "$new_count" -gt 0 ] && extra=" + $new_count new"
    echo "  PASS  $label: $count items identical$extra"
  else
    echo "  FAIL  $label: differences found"
    RESULT=1
  fi
}

# Compare two realm settings objects
compare_realm() {
  local orig="$1" mod="$2" label="$3"
  local a b
  a=$(normalize "$orig")
  b=$(normalize "$mod")

  local diffs
  diffs=$(diff <(echo "$a") <(echo "$b") || true)

  if [ -z "$diffs" ]; then
    local count
    count=$(echo "$a" | jq 'keys | length')
    echo "  PASS  $label: $count settings identical"
  else
    local diff_keys
    diff_keys=$(diff <(echo "$a" | jq -S 'to_entries[]' | jq -s 'sort_by(.key)') \
                     <(echo "$b" | jq -S 'to_entries[]' | jq -s 'sort_by(.key)') \
                | grep '"key"' | sed 's/.*"key": *"\(.*\)".*/\1/' | sort -u || true)
    local count
    count=$(echo "$diff_keys" | grep -c . || true)
    echo "  WARN  $label: $count setting(s) differ:"
    echo "$diff_keys" | sed 's/^/         /'
  fi
}

# ── Test one realm variant ───────────────────────────────────────────

test_variant() {
  local variant_name="$1" original_url="$2" slim_json="$3"

  echo ""
  echo "--- $variant_name ---"
  echo "  Downloading original..."
  curl -sfL "$original_url" -o "$WORK/original-realm.json"

  # A: Original monolith
  docker rm -f kc-validate-a 2>/dev/null || true
  docker run --rm -d --name kc-validate-a \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
    -v "$WORK/original-realm.json:/opt/keycloak/data/import/${REALM}-realm.json:ro" \
    "$KC_IMAGE" start-dev --import-realm
  wait_for_kc kc-validate-a
  export_all kc-validate-a "$WORK/${variant_name}-orig"
  docker stop kc-validate-a 2>/dev/null || true

  # B: Slim realm + modular pipeline
  docker rm -f kc-validate-b 2>/dev/null || true
  docker run --rm -d --name kc-validate-b \
    -e KC_BOOTSTRAP_ADMIN_USERNAME=admin -e KC_BOOTSTRAP_ADMIN_PASSWORD=admin \
    -e KEYCLOAK_ADMIN=admin -e KEYCLOAK_ADMIN_PASSWORD=admin \
    -e OC_DOMAIN=cloud.opencloud.test \
    -v "$SCRIPT_DIR/docker-entrypoint-override.sh:/opt/keycloak/bin/docker-entrypoint-override.sh:ro" \
    -v "$SCRIPT_DIR/00-wait-for-keycloak.sh:/opt/keycloak/bin/00-wait-for-keycloak.sh:ro" \
    -v "$SCRIPT_DIR/10-import-clients.sh:/opt/keycloak/bin/10-import-clients.sh:ro" \
    -v "$SCRIPT_DIR/11-assign-client-scopes.sh:/opt/keycloak/bin/11-assign-client-scopes.sh:ro" \
    -v "$slim_json:/opt/keycloak/data/import-dist/openCloud-realm.json:ro" \
    -v "$SCRIPT_DIR/clients:/opt/keycloak/data/clients:ro" \
    --entrypoint "/bin/sh" \
    "$KC_IMAGE" /opt/keycloak/bin/docker-entrypoint-override.sh start-dev --import-realm
  wait_for_pipeline kc-validate-b
  export_all kc-validate-b "$WORK/${variant_name}-mod"
  docker stop kc-validate-b 2>/dev/null || true

  # Compare
  echo ""
  echo "  Clients:"
  compare_by_key "$WORK/${variant_name}-orig-clients.json" "$WORK/${variant_name}-mod-clients.json" "clients" "clientId"

  echo ""
  echo "  Client Scopes:"
  compare_by_key "$WORK/${variant_name}-orig-client-scopes.json" "$WORK/${variant_name}-mod-client-scopes.json" "client-scopes" "name"

  echo ""
  echo "  Roles:"
  compare_by_key "$WORK/${variant_name}-orig-roles.json" "$WORK/${variant_name}-mod-roles.json" "roles" "name"

  echo ""
  echo "  Groups:"
  compare_by_key "$WORK/${variant_name}-orig-groups.json" "$WORK/${variant_name}-mod-groups.json" "groups" "name"

  echo ""
  echo "  Realm Settings:"
  compare_realm "$WORK/${variant_name}-orig-realm.json" "$WORK/${variant_name}-mod-realm.json" "realm-settings"
}

# ══════════════════════════════════════════════════════════════════════

echo ""
echo "Test 1: LDAP realm"
test_variant "ldap" \
  "$RAW_BASE/opencloud-realm.dist.json" \
  "$SCRIPT_DIR/opencloud-realm.dist.json"

echo ""
echo "Test 2: Autoprovisioning realm"
test_variant "auto" \
  "$RAW_BASE/opencloud-realm-autoprovisioning.dist.json" \
  "$SCRIPT_DIR/opencloud-realm-autoprovisioning.dist.json"

echo ""
if [ $RESULT -eq 0 ]; then
  echo "=== All tests passed ==="
else
  echo "=== FAILURES detected ==="
fi
exit $RESULT
