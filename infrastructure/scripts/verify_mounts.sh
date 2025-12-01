#!/bin/bash
#
# verify_mounts.sh - Verify disk mounts are correct
# Part of Theatre project provisioning scripts
#
# This script verifies that all required mounts are in place.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Verifies that all required disk mounts are in place.

Options:
    -m, --mount PATH       Media disk mount point (default: /mnt/disks/media)
    -c, --clear PATH       gocryptfs clear mount point (default: /srv/library_clear)
    -h, --help             Show this help message

Environment Variables:
    MOUNT_POINT            Override media disk mount point
    MOUNT_CLEAR            Override gocryptfs clear mount point

Examples:
    $(basename "$0")
    $(basename "$0") --mount /mnt/data --clear /srv/clear
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mount)
                MOUNT_POINT="$2"
                shift 2
                ;;
            -c|--clear)
                MOUNT_CLEAR="$2"
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

# Verify media disk mount
verify_media_mount() {
    log "Verifying media disk mount at ${MOUNT_POINT}..."

    if mountpoint -q "${MOUNT_POINT}"; then
        log_success "Media disk is mounted at ${MOUNT_POINT}"
        return 0
    else
        log_error "Media disk is NOT mounted at ${MOUNT_POINT}"
        return 1
    fi
}

# Verify gocryptfs mount
verify_gocryptfs_mount() {
    log "Verifying gocryptfs mount at ${MOUNT_CLEAR}..."

    if mountpoint -q "${MOUNT_CLEAR}"; then
        log_success "gocryptfs is mounted at ${MOUNT_CLEAR}"
        return 0
    else
        log_warn "gocryptfs is NOT mounted at ${MOUNT_CLEAR}"
        log_warn "This may be expected if gocryptfs was not initialized"
        return 0  # Not a fatal error
    fi
}

# Print mount summary
print_summary() {
    log "Mount summary:"
    echo ""
    mount | grep -E "(${MOUNT_POINT}|${MOUNT_CLEAR})" || true
    echo ""
    log "Disk usage:"
    df -h "${MOUNT_POINT}" 2>/dev/null || true
}

main() {
    parse_args "$@"

    local failed=0

    if ! verify_media_mount; then
        failed=1
    fi

    verify_gocryptfs_mount

    print_summary

    if [[ ${failed} -eq 1 ]]; then
        log_error "verify_mounts.sh failed"
        exit 1
    fi

    log_success "verify_mounts.sh completed"
}

main "$@"
