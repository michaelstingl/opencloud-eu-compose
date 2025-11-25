# CLAUDE.md - OpenCloud Compose Repository Guide

This document provides AI assistants with comprehensive context about the OpenCloud Compose repository structure, conventions, and development workflows.

## Project Overview

**OpenCloud Compose** is a Docker Compose-based deployment system for OpenCloud, a file sync and share platform. It provides modular configuration files for various deployment scenarios.

- **Repository**: https://github.com/opencloud-eu/opencloud-compose
- **Official Documentation**: https://docs.opencloud.eu/docs/admin/getting-started/container/docker-compose/docker-compose-base
- **License**: GPLv3

## Repository Structure

```
opencloud-eu-compose/
├── docker-compose.yml          # Core OpenCloud service definition
├── .env.example                # Environment variable template (copy to .env)
├── README.md                   # User documentation
├── LICENSE                     # GPLv3 license
│
├── config/                     # Configuration files
│   ├── opencloud/              # OpenCloud configuration
│   │   ├── csp.yaml            # Content Security Policy
│   │   ├── proxy.yaml          # Proxy routes (for Radicale)
│   │   ├── banned-password-list.txt
│   │   └── apps/               # Web extensions directory
│   │       └── maps/           # Example maps extension
│   ├── keycloak/               # Keycloak configuration
│   │   ├── opencloud-realm.dist.json           # Shared User Directory mode
│   │   ├── opencloud-realm-autoprovisioning.dist.json  # Autoprovisioning mode
│   │   ├── docker-entrypoint-override.sh
│   │   ├── themes/opencloud/   # Custom Keycloak theme
│   │   └── clients/            # OIDC client configurations
│   ├── ldap/                   # LDAP configuration
│   │   ├── ldif/               # LDAP initialization files
│   │   ├── schemas/            # Custom LDAP schemas
│   │   └── docker-entrypoint-override.sh
│   ├── traefik/
│   │   └── dynamic/            # Dynamic Traefik configuration (for certs)
│   └── radicale/               # CalDAV/CardDAV server config
│
├── traefik/                    # Traefik reverse proxy compose files
│   ├── opencloud.yml           # OpenCloud routing
│   ├── collabora.yml           # Collabora routing
│   └── ldap-keycloak.yml       # Keycloak routing
│
├── external-proxy/             # For use with external reverse proxies
│   ├── opencloud.yml           # Exposes port 9200
│   ├── opencloud-exposed.yml   # Alternative exposure config
│   ├── collabora.yml           # Exposes ports 9980, 9300
│   ├── collabora-exposed.yml   # Alternative exposure config
│   ├── keycloak.yml            # Keycloak external proxy
│   └── keycloak-exposed.yml    # Alternative exposure config
│
├── weboffice/                  # Office suite integrations
│   └── collabora.yml           # Collabora Online service
│
├── idm/                        # Identity Management configurations
│   ├── ldap-keycloak.yml       # Keycloak + LDAP (Shared User Directory)
│   ├── external-idp.yml        # External IdP with auto-provisioning
│   └── external-authelia.yml   # Authelia integration
│
├── search/                     # Full-text search
│   └── tika.yml                # Apache Tika for content extraction
│
├── storage/                    # Storage backends
│   └── decomposeds3.yml        # S3-compatible storage driver
│
├── antivirus/                  # Security scanning
│   └── clamav.yml              # ClamAV virus scanning
│
├── monitoring/                 # Observability
│   ├── monitoring.yml          # Metrics endpoints
│   └── monitoring-collaboration.yml  # Collaboration metrics
│
├── radicale/                   # Calendar/Contacts
│   └── radicale.yml            # Radicale CalDAV/CardDAV server
│
├── testing/                    # Testing/development helpers
│   ├── external-keycloak.yml   # Test Keycloak setup
│   └── ldap-manager.yml        # LDAP management UI
│
├── certs/                      # SSL certificates (gitignored)
│   └── .gitkeep
│
└── custom/                     # Custom compose overrides (gitignored)
```

## Modular Compose Architecture

The project uses Docker Compose's file merging capability. Compose files are combined using:
- The `COMPOSE_FILE` environment variable (colon-separated paths)
- Or explicit `-f` flags

### Core Compose Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | **Always required** - Core OpenCloud service |
| `traefik/opencloud.yml` | Traefik reverse proxy with Let's Encrypt |
| `weboffice/collabora.yml` | Collabora Online document editing |
| `idm/ldap-keycloak.yml` | Keycloak + LDAP identity management |
| `search/tika.yml` | Full-text search with Apache Tika |
| `antivirus/clamav.yml` | ClamAV virus scanning |
| `monitoring/monitoring.yml` | Prometheus metrics endpoints |
| `radicale/radicale.yml` | CalDAV/CardDAV calendar/contacts |
| `storage/decomposeds3.yml` | S3 storage backend |

### Common Deployment Combinations

```bash
# Minimal: OpenCloud + Traefik
COMPOSE_FILE=docker-compose.yml:traefik/opencloud.yml

# With Collabora document editing
COMPOSE_FILE=docker-compose.yml:weboffice/collabora.yml:traefik/opencloud.yml:traefik/collabora.yml

# With Keycloak/LDAP identity management
COMPOSE_FILE=docker-compose.yml:idm/ldap-keycloak.yml:traefik/opencloud.yml:traefik/ldap-keycloak.yml

# Full stack with Collabora + Keycloak
COMPOSE_FILE=docker-compose.yml:weboffice/collabora.yml:idm/ldap-keycloak.yml:traefik/opencloud.yml:traefik/collabora.yml:traefik/ldap-keycloak.yml

# External proxy (no Traefik)
COMPOSE_FILE=docker-compose.yml:weboffice/collabora.yml:external-proxy/opencloud.yml:external-proxy/collabora.yml
```

## Key Environment Variables

Variables are defined in `.env` (copy from `.env.example`). Critical variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `OC_DOMAIN` | `cloud.opencloud.test` | Main OpenCloud domain |
| `INITIAL_ADMIN_PASSWORD` | (required) | Admin password - **set before first start** |
| `OC_DOCKER_IMAGE` | `opencloudeu/opencloud-rolling` | Container image |
| `OC_DOCKER_TAG` | `latest` | Image version tag |
| `INSECURE` | `true` | Skip SSL validation (disable for production) |
| `COMPOSE_FILE` | - | Colon-separated compose files |
| `TRAEFIK_SERVICES_TLS_CONFIG` | `tls.certresolver=letsencrypt` | TLS configuration |
| `COLLABORA_DOMAIN` | `collabora.opencloud.test` | Collabora subdomain |
| `KEYCLOAK_DOMAIN` | `keycloak.opencloud.test` | Keycloak subdomain |

## Services and Ports

| Service | Internal Port | External Port | Description |
|---------|---------------|---------------|-------------|
| OpenCloud | 9200 | - | Main application |
| Traefik | 80, 443 | 80, 443 | Reverse proxy |
| Collabora | 9980 | - | Document editing |
| WOPI Server | 9300 | - | Collabora collaboration |
| Keycloak | 8080 | - | Identity provider |
| LDAP | 1389, 1636 | - | User directory |
| PostgreSQL | 5432 | - | Keycloak database |
| Tika | 9998 | - | Content extraction |
| ClamAV | - | - | Virus scanning (socket) |
| Radicale | 5232 | - | CalDAV/CardDAV |

## Docker Networks

All services use the `opencloud-net` bridge network. For monitoring, the network must be created externally:

```bash
docker network create opencloud-net
```

## File Conventions

### Docker Compose Files
- Service definitions use environment variable substitution: `${VAR:-default}`
- All services include `restart: always` for production resilience
- Logging configured via `LOG_DRIVER` variable (default: `local`)
- User/group IDs configurable via `OC_CONTAINER_UID_GID` (default: `1000:1000`)

### Configuration Files
- `.dist.json` suffix: Template files processed at container startup
- `docker-entrypoint-override.sh`: Custom entrypoint scripts for initialization

### Gitignored Paths
- `.env` - Local environment configuration
- `certs/*` - SSL certificates
- `config/traefik/dynamic/*` - Dynamic Traefik configs
- `config/opencloud/apps/*` - Web extensions (except maps)
- `custom/` - Custom compose overrides

## Development Workflows

### Local Development Setup

```bash
# 1. Clone and configure
git clone https://github.com/opencloud-eu/opencloud-compose.git
cd opencloud-compose
cp .env.example .env

# 2. Edit .env - set required variables
# INITIAL_ADMIN_PASSWORD=your-secure-password

# 3. Add hosts entry (Linux/macOS)
echo "127.0.0.1 cloud.opencloud.test" | sudo tee -a /etc/hosts

# 4. Start services
docker compose -f docker-compose.yml -f traefik/opencloud.yml up -d

# 5. Access at https://cloud.opencloud.test
```

### Using mkcert for Local SSL

```bash
mkcert -install
mkcert -cert-file certs/opencloud.test.crt -key-file certs/opencloud.test.key "*.opencloud.test" opencloud.test
# Set TRAEFIK_SERVICES_TLS_CONFIG="tls=true" in .env
```

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f opencloud
docker compose logs -f keycloak
```

### Updating Services

```bash
docker compose pull
docker compose up -d
```

## Important Notes for AI Assistants

### When Modifying Configuration

1. **Never commit `.env` files** - They contain secrets and are gitignored
2. **Test compose file syntax** before committing:
   ```bash
   docker compose -f docker-compose.yml -f <other-files> config
   ```
3. **Maintain backwards compatibility** - Don't remove environment variable defaults
4. **Document DNS requirements** - Note which subdomains each service needs

### When Adding New Services

1. Create a new compose file in the appropriate directory
2. Use consistent environment variable patterns with defaults
3. Add service to the `opencloud-net` network
4. Include `restart: always` and `logging` configuration
5. Update README.md with usage instructions

### Common Issues

- **Container restart loops**: Usually missing `INITIAL_ADMIN_PASSWORD`
- **SSL errors**: Set `INSECURE=true` for self-signed certs in development
- **Port conflicts**: Use external-proxy configs when ports 80/443 are taken
- **Permission errors**: Ensure data directories are owned by `1000:1000`

### Identity Management Modes

Two mutually exclusive modes for Keycloak:

1. **Shared User Directory** (`idm/ldap-keycloak.yml`): Users managed in Keycloak, stored in shared LDAP
2. **Auto-provisioning** (`idm/external-idp.yml`): Users auto-created on first login from external IdP

### Security Considerations

- Default passwords (`admin`) are for development only
- Production deployments should:
  - Set `INSECURE=false`
  - Use strong passwords
  - Enable Let's Encrypt or provide valid certificates
  - Never expose Traefik dashboard publicly without strong auth

## Testing Changes

```bash
# Validate compose configuration
docker compose -f docker-compose.yml -f <your-files> config > /dev/null

# Test service startup
docker compose -f docker-compose.yml -f <your-files> up -d
docker compose ps
docker compose logs -f

# Clean up
docker compose down -v  # -v removes volumes
```

## Related Resources

- [OpenCloud Documentation](https://docs.opencloud.eu/)
- [OpenCloud GitHub](https://github.com/opencloud-eu/opencloud)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Collabora Online Documentation](https://www.collaboraonline.com/documentation/)
