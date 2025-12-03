#!/bin/bash
#
# ensure_gocryptfs.sh - Setup gocryptfs encrypted filesystem
# Part of Theatre project provisioning scripts
#
# This script installs gocryptfs, creates directories, and mounts
# the encrypted filesystem. It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=provision_common.sh
source "${SCRIPT_DIR}/provision_common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Sets up gocryptfs encrypted filesystem.

Options:
    -e, --encrypted DIR     Encrypted directory path (default: /mnt/disks/media/.library_encrypted)
    -c, --clear DIR         Clear mount point path (default: /srv/library_clear)
    -p, --passfile FILE     Password file path (default: /etc/gocryptfs/passfile)
    -h, --help              Show this help message

Environment Variables:
    ENCRYPTED_DIR           Override encrypted directory path
    MOUNT_CLEAR             Override clear mount point path
    GOCRYPTFS_PASSFILE      Override password file path
    GOCRYPTFS_PASSWORD      Password for gocryptfs (creates passfile if set)

Examples:
    $(basename "$0")
    $(basename "$0") --encrypted /mnt/data/.encrypted --clear /srv/clear
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--encrypted)
                ENCRYPTED_DIR="$2"
                shift 2
                ;;
            -c|--clear)
                MOUNT_CLEAR="$2"
                shift 2
                ;;
            -p|--passfile)
                GOCRYPTFS_PASSFILE="$2"
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

main() {
    parse_args "$@"
    require_root

    # Use shared provisioning functions from provision_common.sh
    provision_gocryptfs_full

    log_success "ensure_gocryptfs.sh completed"
}

main "$@"
