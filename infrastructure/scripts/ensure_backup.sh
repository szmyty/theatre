#!/bin/bash
#
# ensure_backup.sh - Setup backup infrastructure on VM
# Part of Theatre project provisioning scripts
#
# This script configures the backup environment and systemd timer
# for automated backups to GCS. It is idempotent.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Default configuration
BACKUP_ENV_DIR="${BACKUP_ENV_DIR:-/etc/theatre}"
BACKUP_ENV_FILE="${BACKUP_ENV_DIR}/backup.env"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Configures backup infrastructure and installs systemd timer.

Options:
    -b, --bucket BUCKET    GCS bucket name for backups
    -p, --prefix PREFIX    Backup prefix in bucket (default: theatre-backup)
    -h, --help             Show this help message

Environment Variables:
    BACKUP_BUCKET          GCS bucket name (e.g., gs://my-backup-bucket)
    BACKUP_PREFIX          Prefix in bucket (default: theatre-backup)

Examples:
    $(basename "$0") --bucket gs://my-backup-bucket
    BACKUP_BUCKET=gs://my-backup-bucket $(basename "$0")

Note: Requires Google Cloud SDK to be installed.
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
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Install Google Cloud SDK if not present
ensure_gcloud_installed() {
    log "Checking for Google Cloud SDK..."
    
    if command -v gsutil &>/dev/null; then
        log_success "Google Cloud SDK is already installed"
        return 0
    fi
    
    log "Installing Google Cloud SDK..."
    
    # Add Google Cloud SDK repository
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
        tee /etc/apt/sources.list.d/google-cloud-sdk.list
    
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
        gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
    
    apt-get update -qq
    apt-get install -y -qq google-cloud-cli
    
    log_success "Google Cloud SDK installed"
}

# Create backup environment file
create_backup_env() {
    log "Setting up backup environment..."
    
    if [[ -z "${BACKUP_BUCKET:-}" ]]; then
        log_warn "BACKUP_BUCKET not set, skipping backup environment setup"
        return 0
    fi
    
    mkdir -p "${BACKUP_ENV_DIR}"
    
    cat > "${BACKUP_ENV_FILE}" << EOF
# Theatre backup configuration
BACKUP_BUCKET=${BACKUP_BUCKET}
BACKUP_PREFIX=${BACKUP_PREFIX:-theatre-backup}
JELLYFIN_CONFIG_DIR=${JELLYFIN_CONFIG_DIR:-/mnt/disks/media/jellyfin_config}
GOCRYPTFS_CONF=${GOCRYPTFS_CONF:-/mnt/disks/media/.library_encrypted/gocryptfs.conf}
EOF
    
    chmod 600 "${BACKUP_ENV_FILE}"
    
    log_success "Backup environment file created at ${BACKUP_ENV_FILE}"
}

# Install systemd timer
install_backup_timer() {
    log "Installing backup systemd timer..."
    
    local service_source="${REPO_DIR}/infrastructure/systemd/theatre-backup.service"
    local timer_source="${REPO_DIR}/infrastructure/systemd/theatre-backup.timer"
    
    if [[ ! -f "${service_source}" ]] || [[ ! -f "${timer_source}" ]]; then
        log_warn "Backup systemd files not found in ${REPO_DIR}/infrastructure/systemd/"
        return 0
    fi
    
    cp "${service_source}" /etc/systemd/system/theatre-backup.service
    cp "${timer_source}" /etc/systemd/system/theatre-backup.timer
    
    chmod 644 /etc/systemd/system/theatre-backup.service
    chmod 644 /etc/systemd/system/theatre-backup.timer
    
    systemctl daemon-reload
    
    # Only enable timer if backup bucket is configured
    if [[ -n "${BACKUP_BUCKET:-}" ]]; then
        systemctl enable --now theatre-backup.timer
        log_success "Backup timer installed and enabled"
    else
        log_warn "Backup timer installed but not enabled (BACKUP_BUCKET not set)"
    fi
}

# Run initial backup test
test_backup() {
    log "Testing backup configuration..."
    
    if [[ -z "${BACKUP_BUCKET:-}" ]]; then
        log_warn "BACKUP_BUCKET not set, skipping backup test"
        return 0
    fi
    
    local backup_script="${REPO_DIR}/scripts/backup-to-gcs.sh"
    
    if [[ ! -f "${backup_script}" ]]; then
        log_warn "Backup script not found at ${backup_script}"
        return 0
    fi
    
    # Test gsutil access to bucket
    if gsutil ls "${BACKUP_BUCKET}" &>/dev/null; then
        log_success "Successfully accessed backup bucket ${BACKUP_BUCKET}"
    else
        log_warn "Cannot access backup bucket ${BACKUP_BUCKET}"
        log_warn "Ensure the VM service account has Storage Object Admin role"
        return 0
    fi
    
    log_success "Backup configuration test passed"
}

main() {
    parse_args "$@"
    require_root
    
    ensure_gcloud_installed
    create_backup_env
    install_backup_timer
    test_backup
    
    log_success "ensure_backup.sh completed"
}

main "$@"
