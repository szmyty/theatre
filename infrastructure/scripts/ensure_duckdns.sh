#!/bin/bash
#
# ensure_duckdns.sh - Setup DuckDNS dynamic DNS
# Part of Theatre project provisioning scripts
#
# This script configures DuckDNS environment and installs the systemd
# timer for automatic updates. It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configures DuckDNS dynamic DNS and installs systemd timer.

Options:
    -t, --token TOKEN      DuckDNS authentication token
    -d, --domain DOMAIN    DuckDNS subdomain (without .duckdns.org)
    -h, --help             Show this help message

Environment Variables:
    DUCKDNS_TOKEN          DuckDNS authentication token
    DUCKDNS_DOMAIN         DuckDNS subdomain

Examples:
    $(basename "$0") --token abc123 --domain myserver
    DUCKDNS_TOKEN=abc123 DUCKDNS_DOMAIN=myserver $(basename "$0")
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--token)
                DUCKDNS_TOKEN="$2"
                shift 2
                ;;
            -d|--domain)
                DUCKDNS_DOMAIN="$2"
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

# Create DuckDNS environment file
create_duckdns_env() {
    log "Setting up DuckDNS environment..."

    if [[ -z "${DUCKDNS_TOKEN:-}" ]] || [[ -z "${DUCKDNS_DOMAIN:-}" ]]; then
        log_warn "DUCKDNS_TOKEN or DUCKDNS_DOMAIN not set, skipping DuckDNS setup"
        return 0
    fi

    mkdir -p "${DUCKDNS_ENV_DIR}"

    cat > "${DUCKDNS_ENV_DIR}/duckdns.env" << EOF
DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
DUCKDNS_DOMAIN=${DUCKDNS_DOMAIN}
EOF
    chmod 600 "${DUCKDNS_ENV_DIR}/duckdns.env"

    log_success "DuckDNS environment file created"
}

# Install DuckDNS systemd timer
install_duckdns_timer() {
    log "Installing DuckDNS systemd timer..."

    local service_source="${REPO_DIR}/infrastructure/systemd/duckdns-update.service"
    local timer_source="${REPO_DIR}/infrastructure/systemd/duckdns-update.timer"

    if [[ ! -f "${service_source}" ]] || [[ ! -f "${timer_source}" ]]; then
        log_warn "DuckDNS systemd files not found in ${REPO_DIR}/infrastructure/systemd/"
        return 0
    fi

    cp "${service_source}" /etc/systemd/system/duckdns-update.service
    cp "${timer_source}" /etc/systemd/system/duckdns-update.timer

    chmod 644 /etc/systemd/system/duckdns-update.service
    chmod 644 /etc/systemd/system/duckdns-update.timer

    systemctl daemon-reload
    systemctl enable --now duckdns-update.timer

    log_success "DuckDNS timer installed and enabled"
}

# Run initial DuckDNS update
run_initial_update() {
    log "Running initial DuckDNS update..."

    local update_script="${REPO_DIR}/scripts/update-duckdns.sh"

    if [[ ! -f "${update_script}" ]]; then
        log_warn "DuckDNS update script not found at ${update_script}"
        return 0
    fi

    if [[ -z "${DUCKDNS_TOKEN:-}" ]] || [[ -z "${DUCKDNS_DOMAIN:-}" ]]; then
        log_warn "DUCKDNS_TOKEN or DUCKDNS_DOMAIN not set, skipping initial update"
        return 0
    fi

    # Source environment and run update
    export DUCKDNS_TOKEN
    export DUCKDNS_DOMAIN
    bash "${update_script}" || log_warn "Initial DuckDNS update failed (may be expected on first run)"
}

main() {
    parse_args "$@"
    require_root

    create_duckdns_env
    install_duckdns_timer
    run_initial_update

    log_success "ensure_duckdns.sh completed"
}

main "$@"
