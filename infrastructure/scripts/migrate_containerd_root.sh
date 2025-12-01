#!/bin/bash
#
# migrate_containerd_root.sh - Migrate containerd data to media disk
# Part of Theatre project provisioning scripts
#
# This script migrates containerd data root directory to the media disk
# to prevent "no space left on device" errors on the small root disk.
# It is idempotent - safe to run multiple times.
#
# CRITICAL: This script MUST be run BEFORE migrate_docker_root.sh
# because Docker depends on containerd.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Migrates containerd data root to the media disk.

Options:
    -m, --mount MOUNTPOINT   Media disk mount point (default: /mnt/disks/media)
    -h, --help               Show this help message

Environment Variables:
    MOUNT_POINT              Override default media disk mount point
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

# Install rsync if not available (critical for migration)
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

# Check if containerd is already using the correct root
check_containerd_root() {
    local config_file="/etc/containerd/config.toml"
    
    if [[ ! -f "${config_file}" ]]; then
        log "containerd config file does not exist yet"
        return 1  # Needs migration
    fi
    
    local current_root
    current_root=$(grep -E '^\s*root\s*=' "${config_file}" 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "/var/lib/containerd")
    
    if [[ "${current_root}" == "${CONTAINERD_DATA_ROOT}" ]]; then
        # Config points to correct path, but verify old dir doesn't exist
        if [[ -d /var/lib/containerd ]]; then
            log_warn "containerd config is correct but old directory still exists at /var/lib/containerd"
            return 1  # Needs cleanup
        fi
        log "containerd is already using correct data root at ${current_root}"
        return 0  # Already migrated
    fi
    
    log "containerd is currently using root at ${current_root}, needs migration"
    return 1  # Needs migration
}

# Stop containerd service
stop_containerd() {
    log "Stopping containerd service..."
    systemctl stop containerd 2>/dev/null || true
    
    # Wait for containerd to fully stop
    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        if ! systemctl is-active --quiet containerd 2>/dev/null; then
            log "containerd stopped"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    
    log_warn "containerd may not have fully stopped"
}

# Start containerd service
start_containerd() {
    log "Starting containerd service..."
    systemctl daemon-reload
    systemctl start containerd
    
    # Wait for containerd to be ready
    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        if systemctl is-active --quiet containerd 2>/dev/null; then
            log_success "containerd is running"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done
    
    log_error "containerd failed to start"
    exit 1
}

# Migrate containerd data
migrate_containerd() {
    log "Starting containerd migration to ${CONTAINERD_DATA_ROOT}..."
    
    # Create target directory on media disk
    log "Creating containerd directory on media disk..."
    mkdir -p "${CONTAINERD_DATA_ROOT}"
    
    # Stop containerd before migration
    stop_containerd
    
    # Sync existing data if it exists
    if [[ -d /var/lib/containerd ]]; then
        log "Syncing containerd data to media disk..."
        if ! rsync -aP /var/lib/containerd/ "${CONTAINERD_DATA_ROOT}/"; then
            log_warn "rsync of containerd data may have partially failed"
            # Don't exit - partial sync is better than no sync
        fi
        log_success "containerd data synced"
    else
        log "No existing containerd data to sync"
    fi
    
    # Configure containerd with new root path
    log "Configuring containerd..."
    mkdir -p /etc/containerd
    
    # Generate default config if needed
    if [[ ! -f /etc/containerd/config.toml ]] || grep -q 'root = "/var/lib/containerd"' /etc/containerd/config.toml 2>/dev/null; then
        log "Generating containerd config..."
        if command -v containerd &>/dev/null; then
            containerd config default > /etc/containerd/config.toml
        else
            log_warn "containerd command not available, creating minimal config"
            cat > /etc/containerd/config.toml << EOF
version = 2
root = "${CONTAINERD_DATA_ROOT}"
state = "/run/containerd"
EOF
        fi
    fi
    
    # Update root path in config
    log "Updating containerd root path in config..."
    sed -i "s|root = \"/var/lib/containerd\"|root = \"${CONTAINERD_DATA_ROOT}\"|g" /etc/containerd/config.toml
    chmod 644 /etc/containerd/config.toml
    
    # Verify new directory exists before removing old one
    log "Verifying new containerd directory exists..."
    if [[ ! -d "${CONTAINERD_DATA_ROOT}" ]]; then
        log_error "containerd data root does not exist: ${CONTAINERD_DATA_ROOT}"
        exit 1
    fi
    
    # CRITICAL: Remove old directory BEFORE starting containerd
    # containerd will refuse to use a new root if the old directory still exists
    log "Removing old containerd directory from root disk..."
    rm -rf /var/lib/containerd
    
    # Start containerd with new configuration
    start_containerd
    
    log_success "containerd migration completed"
}

# Verify containerd is using correct root
verify_containerd_root() {
    log "Verifying containerd root..."
    
    local containerd_root
    containerd_root=$(grep -E '^\s*root\s*=' /etc/containerd/config.toml 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "UNKNOWN")
    
    if [[ "${containerd_root}" == "${CONTAINERD_DATA_ROOT}" ]]; then
        log_success "containerd is using correct root: ${containerd_root}"
    else
        log_error "containerd is NOT using correct root!"
        log_error "Expected: ${CONTAINERD_DATA_ROOT}"
        log_error "Actual: ${containerd_root}"
        exit 1
    fi
    
    # Verify old directory no longer exists
    if [[ -d /var/lib/containerd ]]; then
        log_error "Old containerd directory still exists at /var/lib/containerd!"
        log_error "This can cause containerd to use the wrong root"
        exit 1
    fi
    
    log_success "containerd migration verification passed"
}

main() {
    parse_args "$@"
    require_root
    
    if ! check_media_disk; then
        exit 0
    fi
    
    install_rsync
    
    if check_containerd_root; then
        log_success "containerd is already correctly configured"
    else
        migrate_containerd
    fi
    
    verify_containerd_root
    
    log_success "migrate_containerd_root.sh completed"
}

main "$@"
