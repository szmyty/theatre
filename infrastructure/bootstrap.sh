#!/bin/bash
#
# VM Bootstrap Script for Theatre Project
# This script sets up a fresh VM with Docker, gocryptfs, and the theatre stack.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Source common utilities and shared provisioning logic
# shellcheck source=scripts/common.sh
source "${SCRIPT_DIR}/scripts/common.sh"
# shellcheck source=scripts/provision_common.sh
source "${SCRIPT_DIR}/scripts/provision_common.sh"

# Override REPO_DIR to use PROJECT_ROOT for bootstrap context
# (bootstrap runs from within the infrastructure directory, not /opt/theatre/repo)
REPO_DIR="${PROJECT_ROOT}"

# Configuration (using common.sh defaults where available)
SYSTEMD_SERVICE_FILE="/etc/systemd/system/gocryptfs-mount.service"

# Docker and containerd data root configuration
MEDIA_DISK_MOUNT="/mnt/disks/media"
DOCKER_DATA_ROOT="${MEDIA_DISK_MOUNT}/docker"
CONTAINERD_DATA_ROOT="${MEDIA_DISK_MOUNT}/containerd"

# Install Docker using the consolidated install script
install_docker() {
    log "Installing Docker..."
    "${PROJECT_ROOT}/scripts/install_docker.sh"
}

# Migrate Docker and containerd data root to media disk
# This prevents "no space left on device" errors caused by Docker
# storing images, layers, and snapshots on the small root disk.
migrate_docker_data_root() {
    log "Checking Docker and containerd data root migration..."
    
    # Check if media disk is mounted
    if [[ ! -d "${MEDIA_DISK_MOUNT}" ]] || ! mountpoint -q "${MEDIA_DISK_MOUNT}" 2>/dev/null; then
        log "WARNING: Media disk not mounted at ${MEDIA_DISK_MOUNT}, skipping migration"
        return 0
    fi
    
    # Check if migration is needed (Docker using root disk)
    local current_docker_root
    current_docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    
    if [[ "${current_docker_root}" == "/var/lib/docker" ]]; then
        log "Docker is currently using root disk at ${current_docker_root}, migrating..."
        
        # Stop Docker and containerd before migration
        log "Stopping Docker and containerd..."
        systemctl stop docker || true
        systemctl stop containerd || true
        
        # Create new directories on media disk
        log "Creating Docker and containerd directories on media disk..."
        mkdir -p "${DOCKER_DATA_ROOT}"
        mkdir -p "${CONTAINERD_DATA_ROOT}"
        
        # Sync existing data (idempotent)
        log "Syncing existing Docker data to media disk..."
        if [[ -d /var/lib/docker ]]; then
            rsync -aP /var/lib/docker/ "${DOCKER_DATA_ROOT}/" || true
        fi
        log "Syncing existing containerd data to media disk..."
        if [[ -d /var/lib/containerd ]]; then
            rsync -aP /var/lib/containerd/ "${CONTAINERD_DATA_ROOT}/" || true
        fi
        
        # Configure Docker daemon.json with new data-root
        log "Configuring Docker daemon.json..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << EOF
{
  "data-root": "${DOCKER_DATA_ROOT}"
}
EOF
        chmod 644 /etc/docker/daemon.json
        
        # Configure containerd with new root path
        log "Configuring containerd..."
        mkdir -p /etc/containerd
        if [[ ! -f /etc/containerd/config.toml ]] || grep -q 'root = "/var/lib/containerd"' /etc/containerd/config.toml 2>/dev/null; then
            containerd config default > /etc/containerd/config.toml
        fi
        sed -i "s|root = \"/var/lib/containerd\"|root = \"${CONTAINERD_DATA_ROOT}\"|g" /etc/containerd/config.toml
        chmod 644 /etc/containerd/config.toml
        
        # Reload systemd and start services
        log "Reloading systemd and starting Docker and containerd..."
        systemctl daemon-reload
        systemctl start containerd
        systemctl start docker
        
        # Wait for Docker to be ready
        log "Waiting for Docker to be ready..."
        for _ in {1..30}; do
            if docker info &>/dev/null; then
                break
            fi
            sleep 1
        done
        
        # Remove old root-disk directories to free space
        log "Removing old Docker and containerd directories from root disk..."
        rm -rf /var/lib/docker
        rm -rf /var/lib/containerd
        
        log "Docker and containerd migration completed"
    else
        log "Docker is already using media disk at ${current_docker_root}"
        # Ensure Docker and containerd are running
        systemctl start containerd || true
        systemctl start docker || true
    fi
    
    # Verify Docker and containerd are using correct paths
    verify_docker_data_root
}

# Verify Docker and containerd are using the correct data paths
verify_docker_data_root() {
    log "Verifying Docker data root..."
    local docker_root_after
    docker_root_after=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${docker_root_after}" == "${DOCKER_DATA_ROOT}" ]]; then
        log "SUCCESS: Docker is using correct data root: ${docker_root_after}"
    else
        log "WARNING: Docker is NOT using expected data root"
        log "Expected: ${DOCKER_DATA_ROOT}"
        log "Actual: ${docker_root_after}"
    fi
    
    log "Verifying containerd root..."
    local containerd_root_after
    containerd_root_after=$(grep -E '^\s*root\s*=' /etc/containerd/config.toml 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "UNKNOWN")
    
    if [[ "${containerd_root_after}" == "${CONTAINERD_DATA_ROOT}" ]]; then
        log "SUCCESS: containerd is using correct root: ${containerd_root_after}"
    else
        log "WARNING: containerd is NOT using expected root"
        log "Expected: ${CONTAINERD_DATA_ROOT}"
        log "Actual: ${containerd_root_after}"
    fi
}

# Remove stale config/jellyfin directory from repo
# Docker ALWAYS prioritizes an existing host directory over a declared volume,
# which completely overrides our intended volume mapping.
cleanup_stale_config_directory() {
    log "Checking for stale config/jellyfin directory..."
    
    if [[ -d "${PROJECT_ROOT}/config/jellyfin" ]]; then
        log "Removing stale config/jellyfin directory from repo..."
        rm -rf "${PROJECT_ROOT}/config/jellyfin"
        log "Stale directory removed"
    else
        log "No stale config/jellyfin directory found"
    fi
}

# Ensure correct Jellyfin config directory exists on media disk
ensure_jellyfin_config_directory() {
    local jellyfin_config_dir="/mnt/disks/media/jellyfin_config"
    
    log "Ensuring correct Jellyfin config directory exists at ${jellyfin_config_dir}..."
    mkdir -p "${jellyfin_config_dir}"
    chown -R 1000:1000 "${jellyfin_config_dir}"
    chmod 755 "${jellyfin_config_dir}"
    log "Jellyfin config directory ready"
}

# Cleanup stale Jellyfin volumes
cleanup_jellyfin_volumes() {
    log "Checking for stale Jellyfin config volumes..."
    
    # Docker Compose creates implicit volumes with project-name prefixes
    # (e.g., repo_jellyfin_config, theatre_jellyfin_config) which take
    # precedence over updated bind mounts if not explicitly removed.
    local stale_volumes
    stale_volumes=$(docker volume ls --quiet --filter "name=jellyfin" 2>/dev/null || true)
    
    if [[ -n "${stale_volumes}" ]]; then
        log "Found stale Jellyfin volumes, removing..."
        # Use while loop to properly handle volume names with special characters
        while IFS= read -r vol; do
            if [[ -n "${vol}" ]]; then
                log "Removing volume: ${vol}"
                docker volume rm "${vol}" 2>/dev/null || true
            fi
        done <<< "${stale_volumes}"
        log "Stale volumes removed"
    else
        log "No stale Jellyfin volumes found"
    fi
}

# Verify Jellyfin uses correct config mount
verify_jellyfin_mount() {
    log "Verifying Jellyfin uses correct config mount..."
    
    local expected_source="/mnt/disks/media/jellyfin_config"
    local config_source
    config_source=$(docker inspect jellyfin --format='{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    
    if [[ "${config_source}" == "${expected_source}" ]]; then
        log "SUCCESS: Jellyfin is using correct config mount: ${config_source}"
        return 0
    else
        log "ERROR: Jellyfin is NOT using the correct config mount!"
        log "Expected: ${expected_source}"
        log "Actual: ${config_source}"
        log "Full mount configuration:"
        docker inspect jellyfin --format='{{json .Mounts}}' 2>/dev/null || echo "Container not found"
        return 1
    fi
}

# Verify gocryptfs mount is ready before starting containers
verify_gocryptfs_mount_ready() {
    log "Verifying gocryptfs mount is ready..."
    
    if ! mountpoint -q "${MOUNT_CLEAR}"; then
        log_error "gocryptfs clear mount is not available at ${MOUNT_CLEAR}"
        log_error "Please ensure gocryptfs is mounted before starting Docker containers"
        log_error "Run: systemctl start gocryptfs-mount.service"
        return 1
    fi
    
    log_success "gocryptfs clear mount is available at ${MOUNT_CLEAR}"
    return 0
}

# Start docker-compose
start_docker_compose() {
    log "Starting docker-compose..."
    
    # Verify gocryptfs mount before starting containers
    if ! verify_gocryptfs_mount_ready; then
        log_error "Cannot start docker-compose without gocryptfs mount"
        exit 1
    fi
    
    cd "${PROJECT_ROOT}"
    
    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in ${PROJECT_ROOT}"
        exit 1
    fi
    
    # Remove stale config/jellyfin directory from repo
    cleanup_stale_config_directory
    
    # Perform full Docker cleanup before compose
    log "Performing full Docker cleanup..."
    docker compose down --volumes --remove-orphans 2>/dev/null || true
    docker rm -f jellyfin 2>/dev/null || true
    docker volume prune -f 2>/dev/null || true
    
    # Cleanup any remaining jellyfin volumes
    cleanup_jellyfin_volumes
    
    # Ensure correct Jellyfin config directory exists on media disk
    ensure_jellyfin_config_directory
    
    # Start containers
    docker compose up --detach
    
    # Verify correct mount after starting containers
    sleep 5  # Give container time to start
    if ! verify_jellyfin_mount; then
        log_error "Deploy failed - Jellyfin is using incorrect mount"
        exit 1
    fi
    
    log_success "docker-compose started successfully"
}

# Main function
main() {
    log "Starting VM bootstrap..."
    
    require_root
    install_docker
    migrate_docker_data_root
    
    # Use shared provisioning functions for gocryptfs setup
    provision_install_gocryptfs
    provision_configure_fuse
    provision_create_encrypted_dir
    provision_create_mount_point
    provision_setup_gocryptfs_env
    provision_install_gocryptfs_systemd
    
    start_docker_compose
    
    log_success "VM bootstrap completed successfully"
    log ""
    log "Next steps:"
    log "  1. Initialize gocryptfs: gocryptfs --init \"${ENCRYPTED_DIR}\""
    log "  2. Create passfile: (umask 077 && printf '%s' 'your-password' > \"${GOCRYPTFS_ENV_DIR}/passfile\")"
    log "  3. Verify initialization: ls \"${ENCRYPTED_DIR}/gocryptfs.conf\""
    log "  4. Start the mount service: systemctl start gocryptfs-mount.service"
    log "  5. Access Jellyfin at http://localhost:8096"
}

main "$@"
