#!/bin/bash
#
# verify_jellyfin_mount.sh - Verify Jellyfin container uses correct volume mount
# Part of Theatre project provisioning scripts
#
# This script verifies that the Jellyfin container is using the correct
# volume mount for its config directory (on the media disk, not root disk).
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Verifies that the Jellyfin container is using the correct volume mount.

Options:
    -e, --expected PATH    Expected config source path (default: /mnt/disks/media/jellyfin_config)
    -h, --help             Show this help message

Environment Variables:
    JELLYFIN_CONFIG_DIR    Expected config directory path

Examples:
    $(basename "$0")
    $(basename "$0") --expected /mnt/data/jellyfin_config
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--expected)
                JELLYFIN_CONFIG_DIR="$2"
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

# Verify Jellyfin container exists
check_jellyfin_container() {
    log "Checking if Jellyfin container exists..."

    if ! docker inspect jellyfin &>/dev/null; then
        log_error "Jellyfin container not found"
        log_error "Run start_compose.sh first"
        exit 1
    fi

    local status
    status=$(docker inspect --format='{{.State.Status}}' jellyfin 2>/dev/null)
    log "Jellyfin container status: ${status}"
}

# Verify volume mount
verify_mount() {
    log "Verifying Jellyfin config volume mount..."

    local config_source
    config_source=$(docker inspect jellyfin --format='{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")

    if [[ "${config_source}" == "${JELLYFIN_CONFIG_DIR}" ]]; then
        log_success "Jellyfin is using correct config mount: ${config_source}"
        return 0
    else
        log_error "Jellyfin is NOT using the correct config mount!"
        log_error "Expected: ${JELLYFIN_CONFIG_DIR}"
        log_error "Actual: ${config_source}"
        log ""
        log "Full mount configuration:"
        docker inspect jellyfin --format='{{json .Mounts}}' 2>/dev/null || echo "Unable to inspect container"
        return 1
    fi
}

# Print all mounts for debugging
print_mount_details() {
    log "Jellyfin mount details:"
    docker inspect jellyfin --format='{{range .Mounts}}Source: {{.Source}} -> Destination: {{.Destination}}
{{end}}' 2>/dev/null || echo "Unable to inspect container"
}

main() {
    parse_args "$@"

    check_jellyfin_container

    if ! verify_mount; then
        print_mount_details
        log_error "verify_jellyfin_mount.sh failed"
        exit 1
    fi

    log_success "verify_jellyfin_mount.sh completed"
}

main "$@"
