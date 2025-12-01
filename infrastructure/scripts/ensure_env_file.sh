#!/bin/bash
#
# ensure_env_file.sh - Create .env file for docker-compose
# Part of Theatre project provisioning scripts
#
# This script creates the .env file required by docker-compose
# with the necessary configuration variables.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Creates the .env file for docker-compose.

Options:
    -d, --domain DOMAIN    Domain name for the service
    -t, --token TOKEN      DuckDNS token
    -r, --repo DIR         Repository directory (default: /opt/theatre/repo)
    -h, --help             Show this help message

Environment Variables:
    DOMAIN_NAME            Domain name for the service
    DUCKDNS_TOKEN          DuckDNS authentication token
    REPO_DIR               Repository directory path

Examples:
    $(basename "$0") --domain myserver.duckdns.org --token abc123
    DOMAIN_NAME=myserver.duckdns.org DUCKDNS_TOKEN=abc123 $(basename "$0")
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            -t|--token)
                DUCKDNS_TOKEN="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_DIR="$2"
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

# Create .env file
create_env_file() {
    log "Writing .env file for docker-compose..."

    local env_path="${REPO_DIR}/.env"

    cat > "${env_path}" << EOF
DOMAIN_NAME=${DOMAIN_NAME:-movietheatre.duckdns.org}
DUCKDNS_TOKEN=${DUCKDNS_TOKEN:-}
JELLYFIN_URL=https://${DOMAIN_NAME:-movietheatre.duckdns.org}
EOF

    # Set correct ownership and permissions so docker-compose can read it
    # Use SUDO_USER if available (when run via sudo), otherwise use current user
    local owner="${SUDO_USER:-${USER:-root}}"
    chown "${owner}:${owner}" "${env_path}"
    chmod 644 "${env_path}"

    log_success ".env file written with correct permissions"
}

# Verify .env file
verify_env_file() {
    log "Verifying .env file..."

    local env_path="${REPO_DIR}/.env"

    if [[ ! -f "${env_path}" ]]; then
        log_error ".env file not found at ${env_path}"
        exit 1
    fi

    # Check for required variables
    if grep -Eq "DOMAIN_NAME=.+" "${env_path}"; then
        log_success "DOMAIN_NAME is set"
    else
        log_warn "DOMAIN_NAME is empty or missing"
    fi

    if grep -Eq "DUCKDNS_TOKEN=.+" "${env_path}"; then
        log_success "DUCKDNS_TOKEN is set"
    else
        log_warn "DUCKDNS_TOKEN is empty or missing (HTTPS may not work)"
    fi
}

main() {
    parse_args "$@"
    require_root

    if [[ ! -d "${REPO_DIR}" ]]; then
        log_error "Repository directory not found at ${REPO_DIR}"
        log_error "Run ensure_repo_clone.sh first"
        exit 1
    fi

    create_env_file
    verify_env_file

    log_success "ensure_env_file.sh completed"
}

main "$@"
