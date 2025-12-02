#!/bin/bash
#
# ensure_gocryptfs.sh - Setup gocryptfs encrypted filesystem
# Part of Theatre project provisioning scripts
#
# This script installs gocryptfs, creates directories, and mounts
# the encrypted filesystem. It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Sets up gocryptfs encrypted filesystem.

Options:
    -e, --encrypted DIR     Encrypted directory path (default: /mnt/disks/media/.library_encrypted)
    -c, --clear DIR         Clear mount point path (default: /srv/library_clear)
    -p, --passfile FILE     Password file path (default: /etc/gocryptfs/passfile)
    -h, --help              Show this help message

Environment Variables:
    ENCRYPTED_DIR           Override encrypted directory path
    MOUNT_CLEAR             Override clear mount point path
    GOCRYPTFS_PASSFILE      Override password file path
    GOCRYPTFS_PASSWORD      Password for gocryptfs (creates passfile if set)

Examples:
    $(basename "$0")
    $(basename "$0") --encrypted /mnt/data/.encrypted --clear /srv/clear
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--encrypted)
                ENCRYPTED_DIR="$2"
                shift 2
                ;;
            -c|--clear)
                MOUNT_CLEAR="$2"
                shift 2
                ;;
            -p|--passfile)
                GOCRYPTFS_PASSFILE="$2"
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

# Install fuse3 and gocryptfs
install_gocryptfs() {
    log "Checking fuse3 and gocryptfs..."

    if command -v gocryptfs &>/dev/null && dpkg -s fuse3 &>/dev/null 2>&1; then
        log "fuse3 and gocryptfs already installed"
        return 0
    fi

    log "Installing fuse3 and gocryptfs..."
    apt-get update --quiet
    apt-get install --yes --quiet fuse3 gocryptfs

    log_success "fuse3 and gocryptfs installed"
}

# Ensure user_allow_other is set in fuse.conf
configure_fuse() {
    log "Configuring fuse..."

    if grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        log "user_allow_other already configured"
        return 0
    fi

    echo "user_allow_other" >> /etc/fuse.conf
    log_success "Added user_allow_other to /etc/fuse.conf"
}

# Create encrypted directory
create_encrypted_dir() {
    log "Ensuring encrypted directory ${ENCRYPTED_DIR} exists..."
    mkdir -p "${ENCRYPTED_DIR}"
    chmod 700 "${ENCRYPTED_DIR}"
    log_success "Encrypted directory ready"
}

# Create clear mount point
create_mount_point() {
    log "Ensuring clear mount point ${MOUNT_CLEAR} exists..."
    mkdir -p "${MOUNT_CLEAR}"
    chmod 755 "${MOUNT_CLEAR}"
    log_success "Clear mount point ready"
}

# Setup gocryptfs environment files
setup_gocryptfs_env() {
    log "Setting up gocryptfs environment..."

    mkdir -p "${GOCRYPTFS_ENV_DIR}"
    chmod 700 "${GOCRYPTFS_ENV_DIR}"

    # Create password file if GOCRYPTFS_PASSWORD is set
    # Use subshell with umask 077 for atomic secure file creation
    # This ensures no intermediate insecure state exists
    if [[ -n "${GOCRYPTFS_PASSWORD:-}" ]]; then
        (umask 077 && printf '%s' "${GOCRYPTFS_PASSWORD}" > "${GOCRYPTFS_PASSFILE}")
        log "Password file created"
    fi

    # Create environment file
    local env_file="${GOCRYPTFS_ENV_DIR}/gocryptfs.env"
    cat > "${env_file}" << EOF
GOCRYPTFS_ENCRYPTED_DIR=${ENCRYPTED_DIR}
GOCRYPTFS_MOUNT_POINT=${MOUNT_CLEAR}
GOCRYPTFS_PASSFILE=${GOCRYPTFS_PASSFILE}
EOF
    chmod 600 "${env_file}"
    log_success "Environment file created"
}

# Initialize gocryptfs if not already initialized
initialize_gocryptfs() {
    log "Checking gocryptfs initialization..."

    if [[ -f "${ENCRYPTED_DIR}/gocryptfs.conf" ]]; then
        log "gocryptfs already initialized"
        return 0
    fi

    if [[ ! -f "${GOCRYPTFS_PASSFILE}" ]]; then
        log_warn "Password file not found, skipping gocryptfs initialization"
        log_warn "Create ${GOCRYPTFS_PASSFILE} and run this script again"
        return 0
    fi

    log "Initializing gocryptfs..."
    gocryptfs --init --passfile "${GOCRYPTFS_PASSFILE}" "${ENCRYPTED_DIR}"
    log_success "gocryptfs initialized"
}

# Mount gocryptfs if not already mounted
mount_gocryptfs() {
    log "Checking gocryptfs mount..."

    if mountpoint -q "${MOUNT_CLEAR}"; then
        log "gocryptfs already mounted at ${MOUNT_CLEAR}"
        return 0
    fi

    if [[ ! -f "${ENCRYPTED_DIR}/gocryptfs.conf" ]]; then
        log_warn "gocryptfs not initialized, skipping mount"
        return 0
    fi

    if [[ ! -f "${GOCRYPTFS_PASSFILE}" ]]; then
        log_warn "Password file not found, skipping mount"
        return 0
    fi

    log "Mounting gocryptfs..."
    gocryptfs -allow_other -passfile "${GOCRYPTFS_PASSFILE}" "${ENCRYPTED_DIR}" "${MOUNT_CLEAR}"
    log_success "gocryptfs mounted at ${MOUNT_CLEAR}"
}

# Install systemd service for gocryptfs
install_systemd_service() {
    log "Setting up gocryptfs systemd service..."

    local service_source="${REPO_DIR}/infrastructure/systemd/gocryptfs-mount.service"
    local service_dest="/etc/systemd/system/gocryptfs-mount.service"

    if [[ ! -f "${service_source}" ]]; then
        log_warn "Service file not found at ${service_source}"
        return 0
    fi

    cp "${service_source}" "${service_dest}"
    chmod 644 "${service_dest}"

    systemctl daemon-reload
    systemctl enable gocryptfs-mount.service

    log_success "gocryptfs-mount.service installed and enabled"
}

main() {
    parse_args "$@"
    require_root

    install_gocryptfs
    configure_fuse
    create_encrypted_dir
    create_mount_point
    setup_gocryptfs_env
    initialize_gocryptfs
    mount_gocryptfs
    install_systemd_service

    log_success "ensure_gocryptfs.sh completed"
}

main "$@"
