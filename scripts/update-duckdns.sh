#!/bin/bash
#
# DuckDNS Update Script for Theatre Project
# This script updates the DuckDNS dynamic DNS record with the current public IP.
# Designed to run as a systemd timer every 5 minutes.
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
Usage: ${SCRIPT_NAME}

Updates the DuckDNS dynamic DNS record with the current public IP address.

Required Environment Variables:
    DUCKDNS_TOKEN     Your DuckDNS authentication token
    DUCKDNS_DOMAIN    Your DuckDNS subdomain (without .duckdns.org)

Options:
    -h, --help    Show this help message and exit

Examples:
    DUCKDNS_TOKEN=your-token DUCKDNS_DOMAIN=myserver ${SCRIPT_NAME}

For systemd timer usage, set environment variables in:
    /etc/duckdns/duckdns.env
EOF
}

# Validate required environment variables
validate_env() {
    if [[ -z "${DUCKDNS_TOKEN:-}" ]]; then
        log "ERROR: DUCKDNS_TOKEN environment variable is required"
        exit 1
    fi

    if [[ -z "${DUCKDNS_DOMAIN:-}" ]]; then
        log "ERROR: DUCKDNS_DOMAIN environment variable is required"
        exit 1
    fi
}

# Update DuckDNS record
update_duckdns() {
    local url="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip="
    local response

    log "Updating DuckDNS record for ${DUCKDNS_DOMAIN}.duckdns.org..."

    response=$(curl --silent --fail --show-error "${url}")

    if [[ "${response}" == "OK" ]]; then
        log "DuckDNS update successful"
    else
        log "ERROR: DuckDNS update failed. Response: ${response}"
        exit 1
    fi
}

# Main function
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    validate_env
    update_duckdns
}

main "$@"
