#!/bin/bash
#
# migrate_docker_root.sh - Migrate Docker and containerd data to media disk
# Part of Theatre project provisioning scripts
#
# This script migrates Docker and containerd data root directories to the
# media disk to prevent "no space left on device" errors on the small root disk.
# It is idempotent - safe to run multiple times.
#
# NOTE: For separate containerd migration, use migrate_containerd_root.sh
# This script handles both for backward compatibility, but the order is:
#   1. Stop containerd
#   2. Stop Docker
#   3. Sync data
#   4. Edit configs
#   5. Remove old directories
#   6. Restart containerd
#   7. Restart Docker
#   8. Verify
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

# Install rsync if not available
install_rsync() {
    if ! command -v rsync &>/dev/null; then
        log "Installing rsync..."
        if ! apt-get update --quiet; then
            log_error "Failed to update apt package list"
            exit 1
        fi
        if ! apt-get install --yes rsync; then
            log_error "Failed to install rsync"
            exit 1
        fi
        if ! command -v rsync &>/dev/null; then
            log_error "rsync installation verification failed"
            exit 1
        fi
        log_success "rsync installed"
    fi
}

# Stop Docker and containerd (in correct order)
stop_services() {
    log "Stopping Docker and containerd (in correct order)..."
    
    # Stop Docker first (depends on containerd)
    log "Stopping Docker..."
    systemctl stop docker.socket 2>/dev/null || true
    systemctl stop docker 2>/dev/null || true
    
    # Wait for Docker to stop
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if ! systemctl is-active --quiet docker 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    
    # Then stop containerd
    log "Stopping containerd..."
    systemctl stop containerd 2>/dev/null || true
    
    # Wait for containerd to stop
    attempts=0
    while [[ $attempts -lt 30 ]]; do
        if ! systemctl is-active --quiet containerd 2>/dev/null; then
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    
    log_success "Services stopped"
}

# Start Docker and containerd (in correct order)
start_services() {
    log "Starting containerd and Docker (in correct order)..."
    
    # Reload systemd to pick up config changes
    systemctl daemon-reload
    
    # Start containerd first (Docker depends on it)
    log "Starting containerd..."
    systemctl start containerd
    
    # Wait for containerd to be ready
    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        if systemctl is-active --quiet containerd 2>/dev/null; then
            log "containerd is running"
            break
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    
    if [[ $attempts -ge $max_attempts ]]; then
        log_error "containerd failed to start"
        exit 1
    fi
    
    # Then start Docker
    log "Starting Docker..."
    systemctl start docker

    # Wait for Docker to be ready
    log "Waiting for Docker to be ready..."
    attempts=0
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
    # Check for partial migration state and auto-heal
    log "Checking for partial migration state..."
    
    local current_docker_root
    current_docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    
    # Check if already migrated but old directory still exists (needs cleanup)
    if [[ "${current_docker_root}" == "${DOCKER_DATA_ROOT}" ]]; then
        if [[ -d /var/lib/docker ]] || [[ -d /var/lib/containerd ]]; then
            log_warn "Migration was partially complete - cleaning up old directories..."
            stop_services
            
            # Verify services are actually stopped before removing directories
            if systemctl is-active --quiet docker 2>/dev/null || systemctl is-active --quiet containerd 2>/dev/null; then
                log_error "Services failed to stop, aborting directory cleanup"
                exit 1
            fi
            
            rm -rf /var/lib/docker
            rm -rf /var/lib/containerd
            start_services
            log_success "Partial migration cleanup completed"
        fi
        log "Docker is already using correct data root at ${current_docker_root}"
        return 0
    fi

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
        if ! rsync -aP /var/lib/docker/ "${DOCKER_DATA_ROOT}/"; then
            log_warn "rsync of Docker data may have partially failed, continuing..."
        fi
    fi

    log "Syncing containerd data to media disk..."
    if [[ -d /var/lib/containerd ]]; then
        if ! rsync -aP /var/lib/containerd/ "${CONTAINERD_DATA_ROOT}/"; then
            log_warn "rsync of containerd data may have partially failed, continuing..."
        fi
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

    # Verify new directories exist before removing old ones
    log "Verifying new directories exist before removing old ones..."
    if [[ ! -d "${DOCKER_DATA_ROOT}" ]]; then
        log_error "Docker data root does not exist: ${DOCKER_DATA_ROOT}"
        exit 1
    fi
    if [[ ! -d "${CONTAINERD_DATA_ROOT}" ]]; then
        log_error "containerd data root does not exist: ${CONTAINERD_DATA_ROOT}"
        exit 1
    fi

    # Verify services are actually stopped before removing directories
    log "Verifying services are stopped before removing old directories..."
    if systemctl is-active --quiet docker 2>/dev/null || systemctl is-active --quiet containerd 2>/dev/null; then
        log_error "Services are still running, cannot safely remove old directories"
        exit 1
    fi

    # Remove old directories BEFORE starting services
    # This is critical - containerd refuses to use a new root if the old directory still exists
    log "Removing old directories from root disk..."
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd

    start_services

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
    
    # Verify old directories no longer exist (critical for preventing regression)
    log "Verifying old directories are removed..."
    if [[ -d /var/lib/docker ]]; then
        log_error "Old Docker directory still exists at /var/lib/docker!"
        log_error "This can cause Docker to use the wrong root"
        exit 1
    fi
    if [[ -d /var/lib/containerd ]]; then
        log_error "Old containerd directory still exists at /var/lib/containerd!"
        log_error "This can cause containerd to use the wrong root"
        exit 1
    fi
    log_success "Old directories have been removed"
}

main() {
    parse_args "$@"
    require_root

    if ! check_media_disk; then
        exit 0
    fi

    install_rsync
    migrate_docker_root
    verify_data_roots

    log_success "migrate_docker_root.sh completed"
}

main "$@"
