#!/bin/bash
#
# ensure_disk_mount.sh - Mount media disk and configure fstab
# Part of Theatre project provisioning scripts
#
# This script ensures the media disk is mounted at /mnt/disks/media
# and adds an entry to /etc/fstab for persistent mounting.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Mounts the media disk and configures /etc/fstab for persistence.

Options:
    -d, --device DEVICE      Disk device path (auto-detected via /dev/disk/by-id/)
    -l, --label LABEL        Disk label to search for (default: media)
    -m, --mount MOUNTPOINT   Mount point path (default: /mnt/disks/media)
    -h, --help               Show this help message

Environment Variables:
    DISK_DEVICE              Override disk device path (bypasses auto-detection)
    DISK_LABEL               Label to search for when auto-detecting disk
    MOUNT_POINT              Override default mount point

Disk Discovery Order:
    1. DISK_DEVICE environment variable (if set)
    2. Google Cloud disk by label: /dev/disk/by-id/google-<label>
    3. Filesystem label: /dev/disk/by-label/<label>
    4. First non-boot block device (e.g., /dev/sdb, /dev/vdb)

Examples:
    $(basename "$0")
    $(basename "$0") --device /dev/disk/by-id/google-media --mount /mnt/data
    $(basename "$0") --label data
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
            -l|--label)
                export DISK_LABEL="$2"
                DISK_DEVICE=$(discover_media_disk) || DISK_DEVICE=""
                shift 2
                ;;
            -m|--mount)
                MOUNT_POINT="$2"
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

# Ensure mount point exists
ensure_mount_point() {
    log "Ensuring mount point ${MOUNT_POINT} exists..."
    mkdir -p "${MOUNT_POINT}"
    log_success "Mount point ready"
}

# Add to fstab if not present
# Uses UUID for stability (device paths can change between reboots)
ensure_fstab_entry() {
    if [[ ! -b "${DISK_DEVICE}" ]]; then
        log_warn "Disk device ${DISK_DEVICE} not found, skipping fstab"
        return 0
    fi

    # Get UUID for fstab entry (more stable than device path)
    local disk_uuid
    disk_uuid=$(blkid -s UUID -o value "${DISK_DEVICE}" 2>/dev/null || true)

    if [[ -n "${disk_uuid}" ]]; then
        if grep -q "UUID=${disk_uuid}" /etc/fstab; then
            log "fstab entry for UUID=${disk_uuid} already exists"
            return 0
        fi
        # Also check if device path is in fstab (legacy entry)
        if grep -q "${DISK_DEVICE}" /etc/fstab; then
            log "fstab entry for ${DISK_DEVICE} already exists (consider migrating to UUID)"
            return 0
        fi
        log "Adding UUID=${disk_uuid} to /etc/fstab..."
        echo "UUID=${disk_uuid} ${MOUNT_POINT} ext4 defaults,nofail 0 2" >> /etc/fstab
        log_success "Added fstab entry using UUID"
    else
        # Fallback to device path if UUID is not available
        if grep -q "${DISK_DEVICE}" /etc/fstab; then
            log "fstab entry for ${DISK_DEVICE} already exists"
            return 0
        fi
        log "Adding ${DISK_DEVICE} to /etc/fstab..."
        echo "${DISK_DEVICE} ${MOUNT_POINT} ext4 defaults,nofail 0 2" >> /etc/fstab
        log_success "Added fstab entry using device path"
    fi
}

# Mount disk if not already mounted
ensure_mounted() {
    if [[ ! -b "${DISK_DEVICE}" ]]; then
        log_warn "Disk device ${DISK_DEVICE} not found, skipping mount"
        return 0
    fi

    if mountpoint -q "${MOUNT_POINT}"; then
        log "${MOUNT_POINT} is already mounted"
        return 0
    fi

    log "Mounting ${MOUNT_POINT}..."
    mount "${MOUNT_POINT}"
    log_success "Mounted ${MOUNT_POINT}"
}

main() {
    parse_args "$@"
    require_root

    ensure_mount_point
    ensure_fstab_entry
    ensure_mounted

    log_success "ensure_disk_mount.sh completed"
}

main "$@"
