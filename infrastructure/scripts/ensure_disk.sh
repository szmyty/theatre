#!/bin/bash
#
# ensure_disk.sh - Format media disk if unformatted
# Part of Theatre project provisioning scripts
#
# This script checks if the media disk exists and formats it with ext4 if needed.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Formats the media disk with ext4 filesystem if not already formatted.

Options:
    -d, --device DEVICE    Disk device path (default: /dev/sdb)
    -h, --help             Show this help message

Environment Variables:
    DISK_DEVICE            Override default disk device path

Examples:
    $(basename "$0")
    $(basename "$0") --device /dev/sdc
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--device)
                DISK_DEVICE="$2"
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

# Format disk if not already formatted
ensure_disk_formatted() {
    log "Checking disk ${DISK_DEVICE}..."

    if [[ ! -b "${DISK_DEVICE}" ]]; then
        log_warn "Disk device ${DISK_DEVICE} not found"
        log "This may be expected if running on a VM without attached disk"
        return 0
    fi

    if blkid "${DISK_DEVICE}" &>/dev/null; then
        local fs_type
        fs_type=$(blkid -s TYPE -o value "${DISK_DEVICE}" 2>/dev/null || echo "unknown")
        log_success "Disk ${DISK_DEVICE} is already formatted (${fs_type})"
        return 0
    fi

    log "Formatting ${DISK_DEVICE} as ext4..."
    mkfs.ext4 -F "${DISK_DEVICE}"
    log_success "Disk ${DISK_DEVICE} formatted successfully"
}

main() {
    parse_args "$@"
    require_root
    ensure_disk_formatted
    log_success "ensure_disk.sh completed"
}

main "$@"
