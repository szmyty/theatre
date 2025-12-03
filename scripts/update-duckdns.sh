#!/bin/bash
#
# DuckDNS Update Script for Theatre Project
# This script updates the DuckDNS dynamic DNS record with the current public IP.
# Designed to run as a systemd timer every 5 minutes.
#

set -euo pipefail

# Script name for usage display
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Retry configuration
MAX_RETRIES="${MAX_RETRIES:-5}"
INITIAL_DELAY="${INITIAL_DELAY:-2}"
MAX_DELAY="${MAX_DELAY:-30}"
FAIL_GRACEFULLY="${FAIL_GRACEFULLY:-true}"

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

Optional Environment Variables:
    MAX_RETRIES       Maximum number of retry attempts (default: 5)
    INITIAL_DELAY     Initial delay in seconds between retries (default: 2)
    MAX_DELAY         Maximum delay in seconds between retries (default: 30)
    FAIL_GRACEFULLY   Exit with 0 on failure for systemd timer (default: true)

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

# Update DuckDNS record with retry logic
update_duckdns() {
    local url="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAIN}&token=${DUCKDNS_TOKEN}&ip="
    local response
    local attempt=1
    local delay="${INITIAL_DELAY}"

    log "Updating DuckDNS record for ${DUCKDNS_DOMAIN}.duckdns.org..."

    while [[ ${attempt} -le ${MAX_RETRIES} ]]; do
        log "Attempt ${attempt}/${MAX_RETRIES}..."

        # Attempt the update, capture response even on curl failure
        if response=$(curl --silent --fail --show-error "${url}" 2>&1); then
            if [[ "${response}" == "OK" ]]; then
                log "DuckDNS update successful"
                return 0
            else
                log "WARNING: DuckDNS returned unexpected response: ${response}"
            fi
        else
            log "WARNING: curl request failed: ${response}"
        fi

        # Check if we've exhausted all retries
        if [[ ${attempt} -ge ${MAX_RETRIES} ]]; then
            log "ERROR: DuckDNS update failed after ${MAX_RETRIES} attempts"
            return 1
        fi

        log "Retrying in ${delay} seconds..."
        sleep "${delay}"
        attempt=$((attempt + 1))
        delay=$((delay * 2))  # Exponential backoff
        # Cap the delay at MAX_DELAY
        if [[ ${delay} -gt ${MAX_DELAY} ]]; then
            delay="${MAX_DELAY}"
        fi
    done
}

# Main function
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    validate_env

    if ! update_duckdns; then
        if [[ "${FAIL_GRACEFULLY}" == "true" ]]; then
            log "Continuing gracefully after DuckDNS update failure"
            # Exit with 0 to allow systemd timer to continue scheduling
            exit 0
        else
            log "Exiting with error after DuckDNS update failure"
            exit 1
        fi
    fi
}

main "$@"
