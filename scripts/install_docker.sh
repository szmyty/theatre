#!/bin/bash
#
# Install Docker Script for Theatre Project
# This script installs Docker using the official convenience script.
# It is idempotent - safe to run multiple times.
#

set -euo pipefail

# Script name for usage display
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Helper function for logging
log() {
    echo "[$(date --iso-8601=seconds)] $*"
}

# Display usage help
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Installs Docker using the official Docker convenience script.

Options:
    -h, --help    Show this help message and exit

Examples:
    ${SCRIPT_NAME}
    sudo ${SCRIPT_NAME}

Note: This script must be run as root.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR: Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check if running as root
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log "ERROR: This script must be run as root"
        exit 1
    fi
}

# Install Docker using the official convenience script
install_docker() {
    log "Checking Docker installation..."

    if command -v docker &>/dev/null; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null || echo "unknown")
        log "Docker is already installed: ${docker_version}"
        return 0
    fi

    log "Installing Docker..."

    # Download and run the official Docker installation script
    curl --fail --silent --show-error --location https://get.docker.com | bash

    # Enable and start Docker service
    systemctl enable --now docker

    log "Docker installed successfully"
}

# Verify Docker is running
verify_docker() {
    log "Verifying Docker..."

    if ! systemctl is-active --quiet docker; then
        log "Starting Docker service..."
        systemctl start docker
    fi

    # Wait for Docker to be ready
    local attempts=0
    local max_attempts=30
    while [[ $attempts -lt $max_attempts ]]; do
        if docker info &>/dev/null; then
            local docker_version
            docker_version=$(docker --version 2>/dev/null || echo "unknown")
            log "Docker is running and ready: ${docker_version}"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    log "ERROR: Docker failed to start within ${max_attempts} seconds"
    exit 1
}

# Main function
main() {
    parse_args "$@"
    require_root
    install_docker
    verify_docker
    log "Docker installation complete"
}

main "$@"
