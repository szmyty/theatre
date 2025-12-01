#!/bin/bash
#
# install_dependencies.sh - Install required system dependencies
# Part of Theatre project provisioning scripts
#
# This script installs all required dependencies for the provisioning
# scripts. It must be run before any other provisioning scripts.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Installs required system dependencies for Theatre provisioning.

Options:
    -h, --help    Show this help message

Environment Variables:
    None

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

# List of required packages
REQUIRED_PACKAGES=(
    rsync       # Required for Docker/containerd data migration
    curl        # Required for DuckDNS updates and health checks
    jq          # Required for JSON parsing in diagnostics
    git         # Required for repository clone
    ca-certificates  # Required for HTTPS
    gnupg       # Required for Docker GPG key
)

# Install required packages
install_packages() {
    log "Checking and installing required packages..."

    local packages_to_install=()

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -s "${pkg}" &>/dev/null 2>&1; then
            packages_to_install+=("${pkg}")
        else
            log "Package ${pkg} is already installed"
        fi
    done

    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        log_success "All required packages are already installed"
        return 0
    fi

    log "Installing packages: ${packages_to_install[*]}"

    if ! apt-get update --quiet; then
        log_error "Failed to update apt package list"
        exit 1
    fi

    if ! apt-get install --yes --quiet "${packages_to_install[@]}"; then
        log_error "Failed to install packages"
        exit 1
    fi

    log_success "All packages installed successfully"
}

# Verify all packages are installed
verify_packages() {
    log "Verifying package installation..."

    local failed=0

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if dpkg -s "${pkg}" &>/dev/null 2>&1; then
            log "Package ${pkg} verified"
        else
            log_error "Package ${pkg} is NOT installed"
            failed=1
        fi
    done

    if [[ ${failed} -eq 1 ]]; then
        log_error "Some packages failed to install"
        exit 1
    fi

    log_success "All required packages verified"
}

# Verify critical commands are available
verify_commands() {
    log "Verifying critical commands..."

    local commands=("rsync" "curl" "jq" "git")

    for cmd in "${commands[@]}"; do
        if command -v "${cmd}" &>/dev/null; then
            log "Command ${cmd} is available"
        else
            log_error "Command ${cmd} is NOT available"
            exit 1
        fi
    done

    log_success "All critical commands verified"
}

main() {
    parse_args "$@"
    require_root

    install_packages
    verify_packages
    verify_commands

    log_success "install_dependencies.sh completed"
}

main "$@"
