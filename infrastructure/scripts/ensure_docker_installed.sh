#!/bin/bash
#
# ensure_docker_installed.sh - Install Docker if not present
# Part of Theatre project provisioning scripts
#
# This script calls the consolidated install_docker.sh script to install Docker.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"

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

main() {
    parse_args "$@"
    require_root
    log "Installing Docker using consolidated script..."
    "${PROJECT_ROOT}/scripts/install_docker.sh"
    log_success "ensure_docker_installed.sh completed"
}

main "$@"
