#!/bin/bash
#
# verify_all.sh - Comprehensive verification of Theatre deployment
# Part of Theatre project provisioning scripts
#
# This script verifies all aspects of the Theatre deployment including
# mounts, Docker/containerd data roots, containers, and HTTPS.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive verification of Theatre deployment.

Options:
    -d, --domain DOMAIN    Domain name for HTTPS verification
    --skip-https           Skip HTTPS verification
    --strict               Fail on any warning (not just errors)
    -h, --help             Show this help message

Environment Variables:
    DOMAIN_NAME            Domain name for HTTPS verification

Examples:
    $(basename "$0")
    $(basename "$0") --domain myserver.duckdns.org
    $(basename "$0") --skip-https
EOF
}

# Parse command line arguments
SKIP_HTTPS=false
STRICT_MODE=false
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain)
                DOMAIN_NAME="$2"
                shift 2
                ;;
            --skip-https)
                SKIP_HTTPS=true
                shift
                ;;
            --strict)
                STRICT_MODE=true
                shift
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

# Track verification results
declare -a ERRORS=()
declare -a WARNINGS=()

add_error() {
    ERRORS+=("$1")
    log_error "$1"
}

add_warning() {
    WARNINGS+=("$1")
    log_warn "$1"
}

# Verify media disk mount
verify_media_mount() {
    log "=== Verifying Media Disk Mount ==="
    
    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        log_success "Media disk is mounted at ${MOUNT_POINT}"
        
        # Check disk space
        local usage
        usage=$(df -h "${MOUNT_POINT}" --output=pcent 2>/dev/null | tail -1 | tr -d '% ')
        log "Disk usage: ${usage}%"
        
        if [[ -n "${usage}" ]] && [[ "${usage}" -gt 90 ]]; then
            add_warning "Disk usage is above 90%"
        fi
    else
        add_error "Media disk is NOT mounted at ${MOUNT_POINT}"
    fi
}

# Verify gocryptfs mount
verify_gocryptfs_mount() {
    log "=== Verifying gocryptfs Mount ==="
    
    if mountpoint -q "${MOUNT_CLEAR}" 2>/dev/null; then
        log_success "gocryptfs is mounted at ${MOUNT_CLEAR}"
    else
        add_warning "gocryptfs is NOT mounted at ${MOUNT_CLEAR} (encrypted media unavailable)"
    fi
}

# Verify Docker data root
verify_docker_root() {
    log "=== Verifying Docker Data Root ==="
    
    if ! command -v docker &>/dev/null; then
        add_error "Docker is not installed"
        return
    fi
    
    if ! docker info &>/dev/null; then
        add_error "Docker is not running"
        return
    fi
    
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "UNKNOWN")
    
    if [[ "${docker_root}" == "${DOCKER_DATA_ROOT}" ]]; then
        log_success "Docker is using correct data root: ${docker_root}"
    elif [[ "${docker_root}" == "/var/lib/docker" ]]; then
        add_error "Docker is using root disk at ${docker_root} (should be ${DOCKER_DATA_ROOT})"
    else
        add_warning "Docker data root: ${docker_root} (expected: ${DOCKER_DATA_ROOT})"
    fi
    
    # Check if old directory still exists
    if [[ -d /var/lib/docker ]]; then
        add_warning "Old Docker directory still exists at /var/lib/docker"
    fi
}

# Verify containerd root
verify_containerd_root() {
    log "=== Verifying containerd Root ==="
    
    if [[ ! -f /etc/containerd/config.toml ]]; then
        add_warning "containerd config file not found"
        return
    fi
    
    local containerd_root
    containerd_root=$(grep -E '^\s*root\s*=' /etc/containerd/config.toml 2>/dev/null | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || echo "UNKNOWN")
    
    if [[ "${containerd_root}" == "${CONTAINERD_DATA_ROOT}" ]]; then
        log_success "containerd is using correct root: ${containerd_root}"
    elif [[ "${containerd_root}" == "/var/lib/containerd" ]]; then
        add_error "containerd is using root disk at ${containerd_root} (should be ${CONTAINERD_DATA_ROOT})"
    else
        add_warning "containerd root: ${containerd_root} (expected: ${CONTAINERD_DATA_ROOT})"
    fi
    
    # Check if old directory still exists
    if [[ -d /var/lib/containerd ]]; then
        add_error "Old containerd directory still exists at /var/lib/containerd"
    fi
}

# Verify containers are running
verify_containers() {
    log "=== Verifying Containers ==="
    
    if ! docker info &>/dev/null; then
        log_warn "Docker not available, skipping container verification"
        return
    fi
    
    # Check Jellyfin
    local jellyfin_status
    jellyfin_status=$(docker inspect --format='{{.State.Status}}' jellyfin 2>/dev/null || echo "not_found")
    
    if [[ "${jellyfin_status}" == "running" ]]; then
        log_success "Jellyfin container is running"
    else
        add_error "Jellyfin container status: ${jellyfin_status}"
    fi
    
    # Check Caddy
    local caddy_status
    caddy_status=$(docker inspect --format='{{.State.Status}}' caddy 2>/dev/null || echo "not_found")
    
    if [[ "${caddy_status}" == "running" ]]; then
        log_success "Caddy container is running"
    else
        add_error "Caddy container status: ${caddy_status}"
    fi
}

# Verify Jellyfin config mount
verify_jellyfin_config() {
    log "=== Verifying Jellyfin Config Mount ==="
    
    if ! docker inspect jellyfin &>/dev/null; then
        add_warning "Jellyfin container not found, skipping mount verification"
        return
    fi
    
    local config_source
    config_source=$(docker inspect jellyfin --format='{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    
    if [[ "${config_source}" == "${JELLYFIN_CONFIG_DIR}" ]]; then
        log_success "Jellyfin config mount is correct: ${config_source}"
    else
        add_error "Jellyfin config mount is WRONG: ${config_source} (expected: ${JELLYFIN_CONFIG_DIR})"
    fi
    
    # Check for stale config directory in repo
    if [[ -d "${REPO_DIR}/config/jellyfin" ]]; then
        add_error "Stale config/jellyfin directory exists in repo!"
    fi
}

# Verify no stale volumes
verify_no_stale_volumes() {
    log "=== Verifying No Stale Volumes ==="
    
    if ! docker info &>/dev/null; then
        log_warn "Docker not available, skipping volume verification"
        return
    fi
    
    local stale_volumes
    stale_volumes=$(docker volume ls --quiet --filter "name=jellyfin" 2>/dev/null | grep -v '^caddy' || true)
    
    if [[ -n "${stale_volumes}" ]]; then
        add_warning "Found potentially stale jellyfin volumes:"
        echo "${stale_volumes}"
    else
        log_success "No stale jellyfin volumes found"
    fi
}

# Verify DuckDNS resolution
verify_duckdns() {
    log "=== Verifying DuckDNS Resolution ==="
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        log "No domain name configured, skipping DNS verification"
        return
    fi
    
    local resolved_ip
    resolved_ip=$(dig +short "${DOMAIN_NAME}" 2>/dev/null | head -1 || echo "")
    
    if [[ -n "${resolved_ip}" ]]; then
        log_success "Domain ${DOMAIN_NAME} resolves to ${resolved_ip}"
    else
        add_warning "Domain ${DOMAIN_NAME} does not resolve"
    fi
}

# Verify HTTPS
verify_https() {
    log "=== Verifying HTTPS ==="
    
    if [[ "${SKIP_HTTPS}" == "true" ]]; then
        log "Skipping HTTPS verification (--skip-https)"
        return
    fi
    
    if [[ -z "${DOMAIN_NAME:-}" ]]; then
        log "No domain name configured, skipping HTTPS verification"
        return
    fi
    
    # Allow time for SSL certificate
    log "Checking HTTPS endpoint (this may take a moment)..."
    
    local https_status
    https_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "https://${DOMAIN_NAME}" 2>/dev/null || echo "FAILED")
    
    if [[ "${https_status}" =~ ^(200|302)$ ]]; then
        log_success "HTTPS is working (status: ${https_status})"
    else
        add_warning "HTTPS check returned status: ${https_status}"
    fi
    
    # Check SSL certificate
    local cert_info
    cert_info=$(echo | openssl s_client -connect "${DOMAIN_NAME}:443" -servername "${DOMAIN_NAME}" 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "NO_CERT")
    
    if echo "${cert_info}" | grep -q "notAfter"; then
        log_success "SSL certificate is valid"
    else
        add_warning "Unable to verify SSL certificate"
    fi
}

# Print final summary
print_summary() {
    log ""
    log "============================================================"
    log "                 VERIFICATION SUMMARY"
    log "============================================================"
    log ""
    
    if [[ ${#ERRORS[@]} -eq 0 ]] && [[ ${#WARNINGS[@]} -eq 0 ]]; then
        log_success "All checks passed with no issues!"
        return 0
    fi
    
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        log_error "ERRORS (${#ERRORS[@]}):"
        for err in "${ERRORS[@]}"; do
            log_error "  - ${err}"
        done
        log ""
    fi
    
    if [[ ${#WARNINGS[@]} -gt 0 ]]; then
        log_warn "WARNINGS (${#WARNINGS[@]}):"
        for warn in "${WARNINGS[@]}"; do
            log_warn "  - ${warn}"
        done
        log ""
    fi
    
    log "============================================================"
    
    if [[ ${#ERRORS[@]} -gt 0 ]]; then
        return 1
    fi
    
    if [[ "${STRICT_MODE}" == "true" ]] && [[ ${#WARNINGS[@]} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

main() {
    parse_args "$@"
    
    verify_media_mount
    verify_gocryptfs_mount
    verify_docker_root
    verify_containerd_root
    verify_containers
    verify_jellyfin_config
    verify_no_stale_volumes
    verify_duckdns
    verify_https
    
    if print_summary; then
        log_success "verify_all.sh completed"
    else
        log_error "verify_all.sh completed with issues"
        exit 1
    fi
}

main "$@"
