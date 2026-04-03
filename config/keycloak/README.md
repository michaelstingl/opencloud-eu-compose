# Keycloak Configuration

## Realm Import

On first start, Keycloak imports the realm from one of:

- `opencloud-realm.dist.json` — LDAP/Keycloak shared user directory
- `opencloud-realm-autoprovisioning.dist.json` — auto-provisioning (demo/testing)

The entrypoint replaces `cloud.opencloud.test` with `$OC_DOMAIN` before import.

## Modular Client Definitions

Clients are individual JSON files in `clients/`, imported via a post-start pipeline:

```
clients/
├── web.json + web.scopes
├── OpenCloudAndroid.json + .scopes
├── OpenCloudDesktop.json + .scopes
├── OpenCloudIOS.json + .scopes
└── cyberduck.json + .scopes
```

**Post-start pipeline** (runs in background after Keycloak starts):

| Step | Script | What it does |
|------|--------|-------------|
| 0 | `00-wait-for-keycloak.sh` | Wait for Keycloak, authenticate kcadm.sh |
| 1 | `10-import-clients.sh` | `partialImport` each `clients/*.json` (SKIP existing) |
| 2 | `11-assign-client-scopes.sh` | Assign scopes from `*.scopes` sidecars |

**Adding a client:** drop a `.json` + `.scopes` file in `clients/`, restart Keycloak.

### Why `.scopes` sidecar files?

Keycloak's `partialImport` ignores `defaultClientScopes` from client JSONs
([keycloak#16289](https://github.com/keycloak/keycloak/issues/16289)).
The `.scopes` file works around this — one line, comma-separated scope names:

```
web-origins,profile,roles,groups,basic,email,OpenCloudUnique_ID
```

Scopes that don't exist in the realm are skipped (e.g. `OpenCloudUnique_ID`
only exists in the LDAP variant). When Keycloak fixes #16289, the `.scopes`
files and step 2 can be removed.

## Custom Clients

To add your own clients, mount a directory via Compose override — don't modify this repo:

```yaml
# custom/keycloak-extra-clients.yml
services:
  keycloak:
    volumes:
      - "./my-clients:/opt/keycloak/data/clients-custom:ro"
```

Add to `COMPOSE_FILE` and extend the pipeline to scan the additional path.

## Validation

Proves the modular approach produces an identical realm compared to the monolith:

```bash
bash config/keycloak/validate-modular-clients.sh
```

Requires: docker, jq. Starts throwaway containers, compares clients, scopes, roles,
groups, and realm settings for both LDAP and autoprovisioning variants.

## Debugging

Each pipeline step can be run standalone:

```bash
docker exec keycloak /bin/sh /opt/keycloak/bin/00-wait-for-keycloak.sh
docker exec keycloak /bin/sh /opt/keycloak/bin/10-import-clients.sh
docker exec keycloak /bin/sh /opt/keycloak/bin/11-assign-client-scopes.sh
```
