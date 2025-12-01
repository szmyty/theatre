#!/bin/bash
#
# ensure_docker_installed.sh - Install Docker if not present
# Part of Theatre project provisioning scripts
#
# This script installs Docker and docker-compose using the official
# Docker repository. It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Installs Docker and docker-compose if not already installed.

Options:
    -h, --help    Show this help message

Examples:
    $(basename "$0")
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
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Install Docker from official repository
install_docker() {
    log "Checking Docker installation..."

    if command -v docker &>/dev/null; then
        local docker_version
        docker_version=$(docker --version 2>/dev/null || echo "unknown")
        log_success "Docker is already installed: ${docker_version}"
        return 0
    fi

    log "Installing Docker..."

    # Install prerequisites
    apt-get update --quiet
    apt-get install --yes --quiet ca-certificates curl gnupg

    # Setup Docker GPG key
    install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    # Add Docker repository
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    # Install Docker packages
    apt-get update --quiet
    apt-get install --yes --quiet docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Enable and start Docker
    systemctl enable --now docker

    log_success "Docker installed successfully"
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
            log_success "Docker is running and ready"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 1
    done

    log_error "Docker failed to start within ${max_attempts} seconds"
    exit 1
}

main() {
    parse_args "$@"
    require_root
    install_docker
    verify_docker
    log_success "ensure_docker_installed.sh completed"
}

main "$@"
