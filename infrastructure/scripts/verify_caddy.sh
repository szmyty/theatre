#!/bin/bash
#
# verify_caddy.sh - Verify Caddy container is running
# Part of Theatre project provisioning scripts
#
# This script verifies that the Caddy reverse proxy container is running.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Verifies that the Caddy reverse proxy container is running.

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

# Verify Caddy container exists and is running
verify_caddy_container() {
    log "Checking Caddy container status..."

    if ! docker inspect caddy &>/dev/null; then
        log_error "Caddy container not found"
        return 1
    fi

    local status
    status=$(docker inspect --format='{{.State.Status}}' caddy 2>/dev/null)

    if [[ "${status}" == "running" ]]; then
        log_success "Caddy container is running"
        return 0
    else
        log_error "Caddy container status: ${status}"
        return 1
    fi
}

# Check Caddy container logs for errors
check_caddy_logs() {
    log "Checking Caddy container logs (last 20 lines)..."
    echo ""
    docker logs --tail 20 caddy 2>&1 || true
    echo ""
}

# Verify Caddy is listening on expected ports
verify_caddy_ports() {
    log "Verifying Caddy is listening on ports 80 and 443..."

    local ports
    ports=$(docker port caddy 2>/dev/null || echo "")

    if echo "${ports}" | grep -q "80/tcp"; then
        log_success "Caddy is listening on port 80"
    else
        log_warn "Caddy may not be listening on port 80"
    fi

    if echo "${ports}" | grep -q "443/tcp"; then
        log_success "Caddy is listening on port 443"
    else
        log_warn "Caddy may not be listening on port 443"
    fi
}

main() {
    parse_args "$@"

    if ! verify_caddy_container; then
        check_caddy_logs
        log_error "verify_caddy.sh failed"
        exit 1
    fi

    verify_caddy_ports

    log_success "verify_caddy.sh completed"
}

main "$@"
