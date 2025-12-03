#!/bin/bash
#
# provision_common.sh - Shared provisioning functions for Theatre project
#
# This file contains common provisioning logic shared between bootstrap.sh
# and the workflow provisioning scripts. It is meant to be sourced by
# other scripts and should not be executed directly.
#
# Prerequisites:
#   - Must source common.sh first for logging functions and common paths
#

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script is meant to be sourced, not executed directly." >&2
    exit 1
fi

# Verify common.sh has been sourced (check for log function)
if ! declare -f log &>/dev/null; then
    echo "ERROR: common.sh must be sourced before provision_common.sh" >&2
    exit 1
fi

# =============================================================================
# gocryptfs Provisioning Functions
# =============================================================================

# Install fuse3 and gocryptfs packages
# Idempotent - skips if already installed
provision_install_gocryptfs() {
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

# Configure fuse to allow non-root mounts with allow_other
# Idempotent - skips if already configured
provision_configure_fuse() {
    log "Configuring fuse..."

    if grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        log "user_allow_other already configured"
        return 0
    fi

    echo "user_allow_other" >> /etc/fuse.conf
    log_success "Added user_allow_other to /etc/fuse.conf"
}

# Create encrypted directory for gocryptfs
# Uses ENCRYPTED_DIR from common.sh
provision_create_encrypted_dir() {
    log "Ensuring encrypted directory ${ENCRYPTED_DIR} exists..."
    mkdir -p "${ENCRYPTED_DIR}"
    chmod 700 "${ENCRYPTED_DIR}"
    log_success "Encrypted directory ready"
}

# Create clear mount point for decrypted files
# Uses MOUNT_CLEAR from common.sh
provision_create_mount_point() {
    log "Ensuring clear mount point ${MOUNT_CLEAR} exists..."
    mkdir -p "${MOUNT_CLEAR}"
    chmod 755 "${MOUNT_CLEAR}"
    log_success "Clear mount point ready"
}

# Setup gocryptfs environment files and password file
# Uses GOCRYPTFS_ENV_DIR, GOCRYPTFS_PASSFILE, and GOCRYPTFS_PASSWORD from environment
provision_setup_gocryptfs_env() {
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
# Requires password file to exist
provision_initialize_gocryptfs() {
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
# Requires gocryptfs to be initialized and password file to exist
provision_mount_gocryptfs() {
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

# Install and enable gocryptfs systemd service
# Requires service file to exist in the repository
provision_install_gocryptfs_systemd() {
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

# Verify gocryptfs mount is ready
# Returns 0 if mounted, 1 if not
provision_verify_gocryptfs_mount() {
    log "Verifying gocryptfs mount..."

    if mountpoint -q "${MOUNT_CLEAR}"; then
        log_success "gocryptfs clear mount is available at ${MOUNT_CLEAR}"
        return 0
    fi

    log_error "gocryptfs clear mount is not available at ${MOUNT_CLEAR}"
    return 1
}

# Complete gocryptfs setup - runs all gocryptfs provisioning steps
# This is a convenience function that runs all gocryptfs setup steps in order
provision_gocryptfs_full() {
    provision_install_gocryptfs
    provision_configure_fuse
    provision_create_encrypted_dir
    provision_create_mount_point
    provision_setup_gocryptfs_env
    provision_initialize_gocryptfs
    provision_mount_gocryptfs
    provision_install_gocryptfs_systemd

    # Verify mount status (non-fatal - mount may require manual setup)
    provision_verify_gocryptfs_mount || log_warn "gocryptfs mount verification skipped or failed - manual setup may be required"
}
