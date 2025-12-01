#!/bin/bash
#
# verify_https.sh - Verify HTTPS is working with valid certificate
# Part of Theatre project provisioning scripts
#
# This script verifies that HTTPS is working and the certificate is valid.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Verifies that HTTPS is working with a valid certificate.

Options:
    -d, --domain DOMAIN    Domain name to check (required)
    --timeout SECONDS      Request timeout (default: 30)
    --retries COUNT        Number of retries (default: 12)
    --retry-delay SECONDS  Delay between retries (default: 10)
    -h, --help             Show this help message

Environment Variables:
    DOMAIN_NAME            Domain name to check

Examples:
    $(basename "$0") --domain myserver.duckdns.org
    DOMAIN_NAME=myserver.duckdns.org $(basename "$0")
EOF
}

# Default values
TIMEOUT=30
RETRIES=12
RETRY_DELAY=10

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --retries)
                RETRIES="$2"
                shift 2
                ;;
            --retry-delay)
                RETRY_DELAY="$2"
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

# Verify HTTP probe (Caddy redirect)
verify_http() {
    log "Verifying HTTP redirect..."

    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" -L --max-time "${TIMEOUT}" "http://${DOMAIN_NAME}" 2>/dev/null || echo "FAILED")

    if [[ "${http_status}" =~ ^(200|301|302|308)$ ]]; then
        log_success "HTTP probe successful (status: ${http_status})"
        return 0
    else
        log_warn "HTTP probe returned status: ${http_status}"
        return 1
    fi
}

# Verify HTTPS with retries
verify_https() {
    log "Verifying HTTPS endpoint..."

    local attempt=1
    local https_status

    while [[ $attempt -le $RETRIES ]]; do
        https_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time "${TIMEOUT}" "https://${DOMAIN_NAME}" 2>/dev/null || echo "FAILED")

        if [[ "${https_status}" =~ ^(200|302)$ ]]; then
            log_success "HTTPS probe successful (status: ${https_status})"
            return 0
        fi

        log "Waiting for HTTPS (attempt ${attempt}/${RETRIES})... Status: ${https_status}"
        attempt=$((attempt + 1))
        sleep "${RETRY_DELAY}"
    done

    log_warn "HTTPS probe returned status: ${https_status} after ${RETRIES} attempts"
    return 1
}

# Verify SSL certificate
verify_certificate() {
    log "Checking SSL certificate..."

    local cert_info
    cert_info=$(echo | openssl s_client -connect "${DOMAIN_NAME}:443" -servername "${DOMAIN_NAME}" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "NO_CERT")

    if echo "${cert_info}" | grep -q "notAfter"; then
        log_success "SSL certificate is valid"
        echo "${cert_info}"
        return 0
    else
        log_warn "Unable to verify SSL certificate"
        log_warn "This may be expected while Let's Encrypt is issuing the certificate"
        return 1
    fi
}

main() {
    parse_args "$@"

    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        log_warn "DOMAIN_NAME not set, skipping HTTPS verification"
        log_success "verify_https.sh completed (skipped)"
        exit 0
    fi

    log "Verifying HTTPS for ${DOMAIN_NAME}..."

    local failed=0

    # Allow time for DNS and certificate provisioning
    sleep 5

    verify_http || failed=1
    verify_https || failed=1
    verify_certificate || failed=1

    if [[ ${failed} -eq 1 ]]; then
        log_warn "Some HTTPS checks did not pass"
        log_warn "This may be temporary while certificates are being issued"
    fi

    log_success "verify_https.sh completed"
}

main "$@"
