#!/bin/bash
#
# Backup to GCS Script for Theatre Project
# This script syncs critical Jellyfin config and gocryptfs.conf to Google Cloud Storage.
# Designed to run as a systemd timer or manually.
#

set -euo pipefail

# Script name for usage display
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Default paths
JELLYFIN_CONFIG_DIR="${JELLYFIN_CONFIG_DIR:-/mnt/disks/media/jellyfin_config}"
GOCRYPTFS_CONF="${GOCRYPTFS_CONF:-/mnt/disks/media/.library_encrypted/gocryptfs.conf}"
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

Syncs Jellyfin configuration and gocryptfs.conf to Google Cloud Storage.

Options:
    -b, --bucket BUCKET    GCS bucket name (required)
    -p, --prefix PREFIX    Backup prefix in bucket (default: theatre-backup)
    -h, --help             Show this help message and exit

Required Environment Variables (if not using flags):
    BACKUP_BUCKET          GCS bucket name (e.g., gs://my-backup-bucket)

Optional Environment Variables:
    JELLYFIN_CONFIG_DIR    Path to Jellyfin config (default: /mnt/disks/media/jellyfin_config)
    GOCRYPTFS_CONF         Path to gocryptfs.conf (default: /mnt/disks/media/.library_encrypted/gocryptfs.conf)
    BACKUP_PREFIX          Prefix in bucket (default: theatre-backup)

Examples:
    ${SCRIPT_NAME} --bucket gs://my-backup-bucket
    BACKUP_BUCKET=gs://my-backup-bucket ${SCRIPT_NAME}

Note: Requires gsutil to be installed and authenticated.
EOF
}

# Parse command line arguments
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

# Backup Jellyfin configuration
backup_jellyfin_config() {
    log "Backing up Jellyfin configuration..."

    if [[ ! -d "${JELLYFIN_CONFIG_DIR}" ]]; then
        log "WARNING: Jellyfin config directory not found at ${JELLYFIN_CONFIG_DIR}"
        return 0
    fi

    local dest="${BACKUP_BUCKET}/${BACKUP_PREFIX}/jellyfin_config/"
    
    gsutil -m rsync -r -d "${JELLYFIN_CONFIG_DIR}" "${dest}"
    
    log "Jellyfin configuration backed up to ${dest}"
}

# Backup gocryptfs.conf
backup_gocryptfs_conf() {
    log "Backing up gocryptfs.conf..."

    if [[ ! -f "${GOCRYPTFS_CONF}" ]]; then
        log "WARNING: gocryptfs.conf not found at ${GOCRYPTFS_CONF}"
        return 0
    fi

    local dest="${BACKUP_BUCKET}/${BACKUP_PREFIX}/gocryptfs/"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    
    # Copy with timestamp for versioning (in addition to bucket versioning)
    gsutil cp "${GOCRYPTFS_CONF}" "${dest}gocryptfs.conf"
    gsutil cp "${GOCRYPTFS_CONF}" "${dest}gocryptfs.conf.${timestamp}"
    
    log "gocryptfs.conf backed up to ${dest}"
}

# Create backup manifest
create_manifest() {
    log "Creating backup manifest..."
    
    local manifest_file="/tmp/backup-manifest-$$.json"
    local dest="${BACKUP_BUCKET}/${BACKUP_PREFIX}/manifests/"
    local timestamp
    timestamp=$(date --iso-8601=seconds)
    
    cat > "${manifest_file}" << EOF
{
    "timestamp": "${timestamp}",
    "hostname": "$(hostname)",
    "jellyfin_config_dir": "${JELLYFIN_CONFIG_DIR}",
    "gocryptfs_conf": "${GOCRYPTFS_CONF}",
    "backup_bucket": "${BACKUP_BUCKET}",
    "backup_prefix": "${BACKUP_PREFIX}"
}
EOF
    
    gsutil cp "${manifest_file}" "${dest}manifest-$(date +%Y%m%d-%H%M%S).json"
    gsutil cp "${manifest_file}" "${dest}latest-manifest.json"
    rm -f "${manifest_file}"
    
    log "Backup manifest created"
}

# Main function
main() {
    parse_args "$@"
    validate_requirements
    
    log "Starting backup to ${BACKUP_BUCKET}/${BACKUP_PREFIX}/..."
    
    backup_jellyfin_config
    backup_gocryptfs_conf
    create_manifest
    
    log "Backup completed successfully"
}

main "$@"
