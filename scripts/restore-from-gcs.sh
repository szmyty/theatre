#!/bin/bash
#
# Restore from GCS Script for Theatre Project
# This script restores Jellyfin config and gocryptfs.conf from Google Cloud Storage.
# Use this for disaster recovery.
#

set -euo pipefail

# Script name for usage display
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Default paths
JELLYFIN_CONFIG_DIR="${JELLYFIN_CONFIG_DIR:-/mnt/disks/media/jellyfin_config}"
GOCRYPTFS_DIR="${GOCRYPTFS_DIR:-/mnt/disks/media/.library_encrypted}"
BACKUP_BUCKET="${BACKUP_BUCKET:-}"
BACKUP_PREFIX="${BACKUP_PREFIX:-theatre-backup}"

# Helper function for logging
log() {
    echo "[$(date --iso-8601=seconds)] $*"
}

# Display usage help
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Restores Jellyfin configuration and gocryptfs.conf from Google Cloud Storage.

Options:
    -b, --bucket BUCKET    GCS bucket name (required)
    -p, --prefix PREFIX    Backup prefix in bucket (default: theatre-backup)
    --jellyfin-only        Only restore Jellyfin configuration
    --gocryptfs-only       Only restore gocryptfs.conf
    -h, --help             Show this help message and exit

Required Environment Variables (if not using flags):
    BACKUP_BUCKET          GCS bucket name (e.g., gs://my-backup-bucket)

Optional Environment Variables:
    JELLYFIN_CONFIG_DIR    Path to restore Jellyfin config (default: /mnt/disks/media/jellyfin_config)
    GOCRYPTFS_DIR          Path to encrypted directory (default: /mnt/disks/media/.library_encrypted)
    BACKUP_PREFIX          Prefix in bucket (default: theatre-backup)

Examples:
    ${SCRIPT_NAME} --bucket gs://my-backup-bucket
    ${SCRIPT_NAME} --bucket gs://my-backup-bucket --jellyfin-only
    BACKUP_BUCKET=gs://my-backup-bucket ${SCRIPT_NAME}

Note: Requires gsutil to be installed and authenticated.
IMPORTANT: Stop Jellyfin and unmount gocryptfs before restoring!
EOF
}

# Parse command line arguments
RESTORE_JELLYFIN=true
RESTORE_GOCRYPTFS=true

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--bucket)
                BACKUP_BUCKET="$2"
                shift 2
                ;;
            -p|--prefix)
                BACKUP_PREFIX="$2"
                shift 2
                ;;
            --jellyfin-only)
                RESTORE_GOCRYPTFS=false
                shift
                ;;
            --gocryptfs-only)
                RESTORE_JELLYFIN=false
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log "ERROR: Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate requirements
validate_requirements() {
    if [[ -z "${BACKUP_BUCKET:-}" ]]; then
        log "ERROR: BACKUP_BUCKET is required"
        usage
        exit 1
    fi

    # Ensure bucket starts with gs://
    if [[ ! "${BACKUP_BUCKET}" =~ ^gs:// ]]; then
        BACKUP_BUCKET="gs://${BACKUP_BUCKET}"
    fi

    if ! command -v gsutil &>/dev/null; then
        log "ERROR: gsutil is not installed. Install Google Cloud SDK."
        exit 1
    fi
}

# Check for running services
check_services() {
    log "Checking for running services..."
    
    # Check if Jellyfin is running
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "jellyfin"; then
        log "WARNING: Jellyfin container is running. Consider stopping it first:"
        log "  docker compose down"
    fi
    
    # Check if gocryptfs is mounted
    if mountpoint -q /srv/library_clear 2>/dev/null; then
        log "WARNING: gocryptfs is mounted. Unmount before restoring gocryptfs.conf:"
        log "  fusermount -u /srv/library_clear"
    fi
}

# Restore Jellyfin configuration
restore_jellyfin_config() {
    if [[ "${RESTORE_JELLYFIN}" != "true" ]]; then
        return 0
    fi
    
    log "Restoring Jellyfin configuration..."

    local src="${BACKUP_BUCKET}/${BACKUP_PREFIX}/jellyfin_config/"
    
    # Check if backup exists
    if ! gsutil ls "${src}" &>/dev/null; then
        log "ERROR: Jellyfin backup not found at ${src}"
        return 1
    fi

    # Create target directory if it doesn't exist
    mkdir -p "${JELLYFIN_CONFIG_DIR}"
    
    gsutil -m rsync -r "${src}" "${JELLYFIN_CONFIG_DIR}/"
    
    # Set correct ownership for Jellyfin
    chown -R 1000:1000 "${JELLYFIN_CONFIG_DIR}" 2>/dev/null || true
    
    log "Jellyfin configuration restored to ${JELLYFIN_CONFIG_DIR}"
}

# Restore gocryptfs.conf
restore_gocryptfs_conf() {
    if [[ "${RESTORE_GOCRYPTFS}" != "true" ]]; then
        return 0
    fi
    
    log "Restoring gocryptfs.conf..."

    local src="${BACKUP_BUCKET}/${BACKUP_PREFIX}/gocryptfs/gocryptfs.conf"
    local dest="${GOCRYPTFS_DIR}/gocryptfs.conf"
    
    # Check if backup exists
    if ! gsutil ls "${src}" &>/dev/null; then
        log "ERROR: gocryptfs.conf backup not found at ${src}"
        return 1
    fi

    # Create target directory if it doesn't exist
    mkdir -p "${GOCRYPTFS_DIR}"
    
    # Backup existing conf if present
    if [[ -f "${dest}" ]]; then
        local backup_name
        backup_name="${dest}.backup.$(date +%Y%m%d-%H%M%S)"
        log "Backing up existing gocryptfs.conf to ${backup_name}"
        cp "${dest}" "${backup_name}"
    fi
    
    gsutil cp "${src}" "${dest}"
    chmod 600 "${dest}"
    
    log "gocryptfs.conf restored to ${dest}"
}

# Show latest manifest
show_manifest() {
    log "Fetching backup manifest..."
    
    local manifest="${BACKUP_BUCKET}/${BACKUP_PREFIX}/manifests/latest-manifest.json"
    
    if gsutil ls "${manifest}" &>/dev/null; then
        log "Latest backup manifest:"
        gsutil cat "${manifest}"
    else
        log "No manifest found at ${manifest}"
    fi
}

# Main function
main() {
    parse_args "$@"
    validate_requirements
    
    log "Starting restore from ${BACKUP_BUCKET}/${BACKUP_PREFIX}/..."
    
    show_manifest
    check_services
    
    restore_jellyfin_config
    restore_gocryptfs_conf
    
    log "Restore completed successfully"
    log ""
    log "Next steps:"
    log "  1. Start gocryptfs mount: sudo systemctl start gocryptfs-mount"
    log "  2. Start Jellyfin: docker compose up -d"
}

main "$@"
