#!/bin/bash
#
# VM Bootstrap Script for Theatre Project
# This script sets up a fresh VM with Docker, gocryptfs, and the theatre stack.
#

set -euo pipefail

# Configuration
ENCRYPTED_DIR="/srv/library_encrypted"
MOUNT_POINT="/srv/library_clear"
GOCRYPTFS_ENV_DIR="/etc/gocryptfs"
GOCRYPTFS_ENV_FILE="${GOCRYPTFS_ENV_DIR}/gocryptfs.env"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/gocryptfs-mount.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Helper function for logging
log() {
    echo "[$(date --iso-8601=seconds)] $*"
}

# Check if running as root
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

# Install Docker using the official convenience script
install_docker() {
    log "Installing Docker..."
    
    if command -v docker &>/dev/null; then
        log "Docker is already installed"
        return 0
    fi
    
    # Download and run the official Docker installation script
    curl --fail --silent --show-error --location https://get.docker.com | bash
    
    # Enable and start Docker service
    systemctl enable --now docker
    
    log "Docker installed successfully"
}

# Install gocryptfs
install_gocryptfs() {
    log "Installing gocryptfs..."
    
    if command -v gocryptfs &>/dev/null; then
        log "gocryptfs is already installed"
        return 0
    fi
    
    # Update package list and install gocryptfs
    apt-get update --quiet
    apt-get install --yes --quiet gocryptfs fuse
    
    log "gocryptfs installed successfully"
}

# Create encrypted backing directory
create_encrypted_directory() {
    log "Creating encrypted backing directory at ${ENCRYPTED_DIR}..."
    
    if [[ -d "${ENCRYPTED_DIR}" ]]; then
        log "Encrypted directory already exists"
        return 0
    fi
    
    mkdir --parents "${ENCRYPTED_DIR}"
    chmod 700 "${ENCRYPTED_DIR}"
    
    log "Encrypted directory created successfully"
}

# Create decrypted mount directory
create_mount_directory() {
    log "Creating decrypted mount directory at ${MOUNT_POINT}..."
    
    if [[ -d "${MOUNT_POINT}" ]]; then
        log "Mount directory already exists"
        return 0
    fi
    
    mkdir --parents "${MOUNT_POINT}"
    chmod 755 "${MOUNT_POINT}"
    
    log "Mount directory created successfully"
}

# Setup gocryptfs environment file
setup_gocryptfs_env() {
    log "Setting up gocryptfs environment file..."
    
    mkdir --parents "${GOCRYPTFS_ENV_DIR}"
    
    if [[ ! -f "${GOCRYPTFS_ENV_FILE}" ]]; then
        cat > "${GOCRYPTFS_ENV_FILE}" << EOF
# gocryptfs configuration
GOCRYPTFS_ENCRYPTED_DIR=${ENCRYPTED_DIR}
GOCRYPTFS_MOUNT_POINT=${MOUNT_POINT}
GOCRYPTFS_PASSFILE=${GOCRYPTFS_ENV_DIR}/passfile
EOF
        chmod 600 "${GOCRYPTFS_ENV_FILE}"
        log "Created gocryptfs environment file"
        log "WARNING: You must create ${GOCRYPTFS_ENV_DIR}/passfile with your encryption password"
    else
        log "gocryptfs environment file already exists"
    fi
}

# Install and enable systemd service
enable_systemd_service() {
    log "Enabling systemd service..."
    
    # Copy the systemd service file from the project
    local service_source="${SCRIPT_DIR}/systemd/gocryptfs-mount.service"
    
    if [[ -f "${service_source}" ]]; then
        cp --force "${service_source}" "${SYSTEMD_SERVICE_FILE}"
        chmod 644 "${SYSTEMD_SERVICE_FILE}"
    else
        log "ERROR: Service file not found at ${service_source}"
        exit 1
    fi
    
    # Reload systemd and enable the service
    systemctl daemon-reload
    systemctl enable gocryptfs-mount.service
    
    log "Systemd service enabled successfully"
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

# Start docker-compose
start_docker_compose() {
    log "Starting docker-compose..."
    
    cd "${PROJECT_ROOT}"
    
    if [[ ! -f "docker-compose.yml" ]]; then
        log "ERROR: docker-compose.yml not found in ${PROJECT_ROOT}"
        exit 1
    fi
    
    # Stop any existing containers before restarting
    log "Stopping existing containers..."
    docker compose down --remove-orphans 2>/dev/null || true
    
    # Check if jellyfin container was using a named volume instead of bind mount
    local mount_type
    mount_type=$(docker inspect jellyfin --format='{{range .Mounts}}{{if eq .Destination "/config"}}{{.Type}}{{end}}{{end}}' 2>/dev/null || echo "")
    if [[ "${mount_type}" == "volume" ]]; then
        log "Detected jellyfin using named volume for /config, forcing volume removal..."
        docker compose down --volumes --remove-orphans 2>/dev/null || true
    fi
    
    # Cleanup any remaining jellyfin volumes
    cleanup_jellyfin_volumes
    
    docker compose up --detach
    
    log "docker-compose started successfully"
}

# Main function
main() {
    log "Starting VM bootstrap..."
    
    check_root
    install_docker
    install_gocryptfs
    create_encrypted_directory
    create_mount_directory
    setup_gocryptfs_env
    enable_systemd_service
    start_docker_compose
    
    log "VM bootstrap completed successfully"
    log ""
    log "Next steps:"
    log "  1. Initialize gocryptfs: gocryptfs --init \"${ENCRYPTED_DIR}\""
    log "  2. Create passfile: echo 'your-password' > \"${GOCRYPTFS_ENV_DIR}/passfile\" && chmod 600 \"${GOCRYPTFS_ENV_DIR}/passfile\""
    log "  3. Verify initialization: ls \"${ENCRYPTED_DIR}/gocryptfs.conf\""
    log "  4. Start the mount service: systemctl start gocryptfs-mount.service"
    log "  5. Access Jellyfin at http://localhost:8096"
}

main "$@"
