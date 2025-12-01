#!/bin/bash
#
# migrate_docker_root.sh - Migrate Docker and containerd data to media disk
# Part of Theatre project provisioning scripts
#
# This script migrates Docker and containerd data root directories to the
# media disk to prevent "no space left on device" errors on the small root disk.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Migrates Docker and containerd data root to the media disk.

Options:
    -m, --mount MOUNTPOINT   Media disk mount point (default: /mnt/disks/media)
    -h, --help               Show this help message

Environment Variables:
    MOUNT_POINT              Override default media disk mount point
    DOCKER_DATA_ROOT         Override Docker data root path
    CONTAINERD_DATA_ROOT     Override containerd data root path

Examples:
    $(basename "$0")
    $(basename "$0") --mount /mnt/data
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mount)
                MOUNT_POINT="$2"
                DOCKER_DATA_ROOT="${MOUNT_POINT}/docker"
                CONTAINERD_DATA_ROOT="${MOUNT_POINT}/containerd"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check if media disk is mounted
check_media_disk() {
    if [[ ! -d "${MOUNT_POINT}" ]] || ! mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        log_warn "Media disk not mounted at ${MOUNT_POINT}, skipping migration"
        return 1
    fi
    return 0
}

# Stop Docker and containerd
stop_services() {
    log "Stopping Docker and containerd..."
    systemctl stop docker 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    log "Services stopped"
}

# Start Docker and containerd
start_services() {
    log "Starting containerd and Docker..."
    systemctl daemon-reload
    systemctl start containerd
    systemctl start docker

    # Wait for Docker to be ready
    log "Waiting for Docker to be ready..."
    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        if docker info &>/dev/null; then
            log_success "Docker is ready"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    log_error "Docker failed to start"
    exit 1
}

# Migrate Docker data root
migrate_docker_root() {
    local current_docker_root
    current_docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")

    if [[ "${current_docker_root}" != "/var/lib/docker" ]]; then
        log "Docker is already using custom data root at ${current_docker_root}"
        return 0
    fi

    log "Docker is currently using root disk at ${current_docker_root}, migrating..."

    stop_services

    # Create directories on media disk
    log "Creating directories on media disk..."
    mkdir -p "${DOCKER_DATA_ROOT}"
    mkdir -p "${CONTAINERD_DATA_ROOT}"

    # Sync existing data
    log "Syncing Docker data to media disk..."
    if [[ -d /var/lib/docker ]]; then
        rsync -aP /var/lib/docker/ "${DOCKER_DATA_ROOT}/" || true
    fi

    log "Syncing containerd data to media disk..."
    if [[ -d /var/lib/containerd ]]; then
        rsync -aP /var/lib/containerd/ "${CONTAINERD_DATA_ROOT}/" || true
    fi

    # Configure Docker daemon.json
    log "Configuring Docker daemon.json..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
  "data-root": "${DOCKER_DATA_ROOT}"
}
EOF
    chmod 644 /etc/docker/daemon.json

    # Configure containerd
    log "Configuring containerd..."
    mkdir -p /etc/containerd
    if [[ ! -f /etc/containerd/config.toml ]] || grep -q 'root = "/var/lib/containerd"' /etc/containerd/config.toml 2>/dev/null; then
        containerd config default > /etc/containerd/config.toml
    fi
    sed -i "s|root = \"/var/lib/containerd\"|root = \"${CONTAINERD_DATA_ROOT}\"|g" /etc/containerd/config.toml
    chmod 644 /etc/containerd/config.toml

    start_services

    # Remove old directories to free space
    log "Removing old directories from root disk..."
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd

    log_success "Docker and containerd migration completed"
}

# Verify correct data roots
verify_data_roots() {
    log "Verifying Docker data root..."
    local docker_root_after
    docker_root_after=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "UNKNOWN")

    if [[ "${docker_root_after}" == "${DOCKER_DATA_ROOT}" ]]; then
        log_success "Docker is using correct data root: ${docker_root_after}"
    else
        log_error "Docker is NOT using correct data root!"
        log_error "Expected: ${DOCKER_DATA_ROOT}"
        log_error "Actual: ${docker_root_after}"
        exit 1
    fi

    log "Verifying containerd root..."
    local containerd_root_after
    containerd_root_after=$(grep -E '^\s*root\s*=' /etc/containerd/config.toml 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "UNKNOWN")

    if [[ "${containerd_root_after}" == "${CONTAINERD_DATA_ROOT}" ]]; then
        log_success "containerd is using correct root: ${containerd_root_after}"
    else
        log_error "containerd is NOT using correct root!"
        log_error "Expected: ${CONTAINERD_DATA_ROOT}"
        log_error "Actual: ${containerd_root_after}"
        exit 1
    fi
}

main() {
    parse_args "$@"
    require_root

    if ! check_media_disk; then
        exit 0
    fi

    migrate_docker_root
    verify_data_roots

    log_success "migrate_docker_root.sh completed"
}

main "$@"
