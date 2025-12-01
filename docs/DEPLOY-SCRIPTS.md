# Deploy Scripts Documentation

This document describes the modular bash scripts used for deploying the Theatre project infrastructure.

## Overview

The deployment process has been refactored from a monolithic GitHub Actions workflow into modular, reusable bash scripts. This improves:

- **Maintainability**: Each script handles a single responsibility
- **Debuggability**: Scripts can be run manually on the VM for troubleshooting
- **Testability**: Individual scripts can be tested in isolation
- **Readability**: The GitHub workflow is now under 200 lines

## Script Directory

All provisioning scripts are located in:

```
infrastructure/scripts/
```

## Scripts

### Setup Scripts

| Script | Description |
|--------|-------------|
| `common.sh` | Shared utilities, logging functions, and common paths |
| `ensure_disk.sh` | Format media disk with ext4 if unformatted |
| `ensure_disk_mount.sh` | Mount media disk and configure /etc/fstab |
| `ensure_docker_installed.sh` | Install Docker and docker-compose |
| `migrate_docker_root.sh` | Migrate Docker data root to media disk |
| `ensure_gocryptfs.sh` | Install and configure gocryptfs encryption |
| `ensure_duckdns.sh` | Configure DuckDNS dynamic DNS |
| `ensure_repo_clone.sh` | Clone or update the theatre repository |
| `ensure_env_file.sh` | Create .env file for docker-compose |
| `ensure_compose_cleanup.sh` | Clean up Docker before starting services |
| `start_compose.sh` | Start Docker Compose services |

### Verification Scripts

| Script | Description |
|--------|-------------|
| `verify_mounts.sh` | Verify disk mounts are correct |
| `verify_jellyfin_mount.sh` | Verify Jellyfin uses correct volume mount |
| `verify_caddy.sh` | Verify Caddy reverse proxy is running |
| `verify_https.sh` | Verify HTTPS is working with valid certificate |
| `diagnostics.sh` | Collect and display system diagnostics |

### GCP Scripts (run from GitHub Actions)

| Script | Description |
|--------|-------------|
| `ensure_vm.sh` | Create VM if it doesn't exist (runs on GH Actions runner) |

## Usage

### From GitHub Actions

The `deploy_full_stack.yml` workflow:

1. Uploads scripts to the VM at `/opt/theatre/scripts/`
2. Runs each script in sequence with appropriate environment variables
3. Verifies the deployment was successful

### Manual Debugging

You can run scripts manually on the VM for debugging:

```bash
# SSH to the VM
gcloud compute ssh theatre-vm --zone us-central1-a

# Run a specific script
sudo /opt/theatre/scripts/ensure_docker_installed.sh

# Run diagnostics
sudo /opt/theatre/scripts/diagnostics.sh --full

# Verify mounts
sudo /opt/theatre/scripts/verify_mounts.sh
```

### Environment Variables

Scripts accept configuration via environment variables:

```bash
# Common variables (set in common.sh)
MOUNT_POINT=/mnt/disks/media
DISK_DEVICE=/dev/sdb
REPO_DIR=/opt/theatre/repo
REPO_URL=https://github.com/szmyty/theatre.git

# Docker variables
DOCKER_DATA_ROOT=/mnt/disks/media/docker
CONTAINERD_DATA_ROOT=/mnt/disks/media/containerd

# gocryptfs variables
ENCRYPTED_DIR=/mnt/disks/media/.library_encrypted
MOUNT_CLEAR=/srv/library_clear
GOCRYPTFS_PASSWORD=<secret>

# DuckDNS variables
DUCKDNS_TOKEN=<secret>
DUCKDNS_DOMAIN=yoursubdomain
DOMAIN_NAME=yoursubdomain.duckdns.org
```

### Command Line Arguments

Most scripts also accept command line arguments:

```bash
# View help for any script
sudo /opt/theatre/scripts/ensure_disk.sh --help

# Override defaults
sudo /opt/theatre/scripts/ensure_disk.sh --device /dev/sdc
sudo /opt/theatre/scripts/ensure_disk_mount.sh --mount /mnt/custom
```

## Script Design Principles

All scripts follow these principles:

1. **Idempotent**: Safe to run multiple times
2. **Fail-fast**: Exit non-zero on failure with `set -euo pipefail`
3. **Logged**: Consistent log format with timestamps
4. **Configurable**: Accept env vars and CLI arguments
5. **Self-documenting**: Include `--help` flag

## Logging

Scripts use consistent logging functions:

```bash
log "Informational message"
log_success "Success message"
log_warn "Warning message"
log_error "Error message"
```

Output format:
```
[2024-01-15T10:30:00+00:00] INFO: Checking Docker installation...
[2024-01-15T10:30:01+00:00] SUCCESS: Docker is already installed
```

## Execution Order

Scripts should be run in this order:

1. `ensure_disk.sh` - Format disk
2. `ensure_disk_mount.sh` - Mount disk
3. `ensure_docker_installed.sh` - Install Docker
4. `migrate_docker_root.sh` - Move Docker data to media disk
5. `ensure_gocryptfs.sh` - Setup encryption
6. `ensure_repo_clone.sh` - Clone repository
7. `ensure_duckdns.sh` - Setup DNS
8. `ensure_env_file.sh` - Create .env
9. `ensure_compose_cleanup.sh` - Clean up Docker
10. `start_compose.sh` - Start services

Verification scripts can be run in any order after deployment.

## Troubleshooting

### View system diagnostics
```bash
sudo /opt/theatre/scripts/diagnostics.sh --full
```

### Check specific components
```bash
# Verify mounts
sudo /opt/theatre/scripts/verify_mounts.sh

# Verify Jellyfin config mount
sudo /opt/theatre/scripts/verify_jellyfin_mount.sh

# Verify HTTPS
sudo DOMAIN_NAME=yourdomain.duckdns.org /opt/theatre/scripts/verify_https.sh
```

### Common issues

1. **Disk not found**: Check if media disk is attached to VM
2. **Docker not starting**: Check Docker data root path
3. **gocryptfs not mounting**: Verify password file exists
4. **HTTPS not working**: Check DuckDNS token and domain
