# Environment Variables

This document defines the naming conventions and environment variables used in the Theatre project.

## Naming Conventions

### General Rules

1. **UPPERCASE_WITH_UNDERSCORES**: All environment variables use uppercase letters with underscores separating words
2. **PREFIX_COMPONENT_PURPOSE**: Variables are named with a service/component prefix, followed by the component and purpose
3. **Semantic Suffixes**: Use consistent suffixes to indicate the type/purpose:
   - `_PASSWORD` - The actual secret password value (sensitive)
   - `_PASSFILE` - Path to a file containing a password
   - `_TOKEN` - An authentication token (sensitive)
   - `_DIR` - A directory path
   - `_URL` - A URL endpoint
   - `_DOMAIN` - A domain name
   - `_NAME` - A name/identifier

### Distinction Between Password and Passfile

- `GOCRYPTFS_PASSWORD`: The actual encryption password (secret value, used during provisioning)
- `GOCRYPTFS_PASSFILE`: Path to the file where the password is stored (e.g., `/etc/gocryptfs/passfile`)

The `_PASSWORD` variable is typically used during initial provisioning to set up the password file, while `_PASSFILE` is used at runtime by services and scripts that need to read the password.

## Environment Variable Reference

### gocryptfs Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `GOCRYPTFS_PASSWORD` | Secret | - | Encryption password (used to create passfile during provisioning) |
| `GOCRYPTFS_PASSFILE` | Path | `/etc/gocryptfs/passfile` | Path to the password file |
| `GOCRYPTFS_ENCRYPTED_DIR` | Path | `/mnt/disks/media/.library_encrypted` | Path to the encrypted backing directory |
| `GOCRYPTFS_MOUNT_POINT` | Path | `/srv/library_clear` | Path where the decrypted filesystem is mounted |
| `GOCRYPTFS_ENV_DIR` | Path | `/etc/gocryptfs` | Directory containing gocryptfs configuration |

### DuckDNS Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `DUCKDNS_TOKEN` | Secret | - | DuckDNS authentication token (for systemd service, not Docker) |
| `DUCKDNS_DOMAIN` | String | - | DuckDNS subdomain (without `.duckdns.org`) |
| `DUCKDNS_ENV_DIR` | Path | `/etc/duckdns` | Directory containing DuckDNS configuration |
| `DOMAIN_NAME` | String | - | Full domain name (e.g., `movietheatre.duckdns.org`) |

> **Note**: For Docker containers, the DuckDNS token is now managed via Docker secrets.
> See `config/secrets/duckdns_token.txt.example` for setup instructions.

### Infrastructure Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `MOUNT_POINT` | Path | `/mnt/disks/media` | Media disk mount point |
| `DISK_DEVICE` | Path | `/dev/sdb` | Disk device path |
| `REPO_DIR` | Path | `/opt/theatre/repo` | Repository clone location |
| `REPO_URL` | URL | `https://github.com/szmyty/theatre.git` | Repository URL |

### Docker Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `DOCKER_DATA_ROOT` | Path | `/mnt/disks/media/docker` | Docker data root directory |
| `CONTAINERD_DATA_ROOT` | Path | `/mnt/disks/media/containerd` | containerd data root directory |

### Jellyfin Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `JELLYFIN_URL` | URL | `http://localhost:8096` | Jellyfin service URL |
| `JELLYFIN_CONFIG_DIR` | Path | `/mnt/disks/media/jellyfin_config` | Jellyfin configuration directory |

## File Locations

### Configuration Files

| File | Purpose |
|------|---------|
| `/etc/gocryptfs/gocryptfs.env` | gocryptfs service environment configuration |
| `/etc/gocryptfs/passfile` | gocryptfs encryption password |
| `/etc/duckdns/duckdns.env` | DuckDNS service environment configuration |
| `/opt/theatre/repo/.env` | Docker Compose environment file |

### Docker Secrets

Docker secrets are stored in `config/secrets/` and mounted into containers at `/run/secrets/`:

| Secret File | Container Path | Purpose |
|-------------|----------------|---------|
| `config/secrets/duckdns_token.txt` | `/run/secrets/duckdns_token` | DuckDNS authentication token for Caddy |

To set up Docker secrets:

1. Copy the example file: `cp config/secrets/duckdns_token.txt.example config/secrets/duckdns_token.txt`
2. Edit the file with your actual token: `nano config/secrets/duckdns_token.txt`
3. Ensure the file has restricted permissions: `chmod 600 config/secrets/duckdns_token.txt`

### Systemd Environment Files

Systemd services load environment variables from these files:

- **gocryptfs-mount.service**: `/etc/gocryptfs/gocryptfs.env`
- **duckdns-update.service**: `/etc/duckdns/duckdns.env`

## GitHub Actions Secrets and Variables

### Repository Secrets (Sensitive)

| Secret | Description |
|--------|-------------|
| `GCP_SA_KEY` | Google Cloud service account key JSON |
| `GCP_PROJECT_ID` | Google Cloud project ID |
| `GCP_ZONE` | Google Cloud zone |
| `GOCRYPTFS_PASSWORD` | gocryptfs encryption password |
| `DUCKDNS_TOKEN` | DuckDNS authentication token |

### Repository Variables (Non-sensitive)

| Variable | Description |
|----------|-------------|
| `GCP_VM_NAME` | VM instance name (default: `theatre-vm`) |
| `GCP_MEDIA_DISK_NAME` | Media disk name (default: `theatre-media-disk`) |
| `DOMAIN_NAME` | Full domain name for HTTPS |
| `DUCKDNS_DOMAIN` | DuckDNS subdomain |
