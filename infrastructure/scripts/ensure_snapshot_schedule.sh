#!/bin/bash
#
# ensure_snapshot_schedule.sh - Create GCP disk snapshot schedule
# Part of Theatre project provisioning scripts
#
# This script creates a GCP snapshot schedule for the media disk
# to enable automated disk-level backups. It is idempotent.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Default configuration
SNAPSHOT_SCHEDULE_NAME="${SNAPSHOT_SCHEDULE_NAME:-theatre-daily-snapshot}"
SNAPSHOT_REGION="${SNAPSHOT_REGION:-us-central1}"
SNAPSHOT_START_TIME="${SNAPSHOT_START_TIME:-04:00}"
SNAPSHOT_RETENTION_DAYS="${SNAPSHOT_RETENTION_DAYS:-7}"
SNAPSHOT_STORAGE_LOCATION="${SNAPSHOT_STORAGE_LOCATION:-us}"
MEDIA_DISK_NAME="${MEDIA_DISK_NAME:-theatre-media-disk}"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Creates a GCP snapshot schedule for automated disk backups.

Options:
    -n, --name NAME            Snapshot schedule name (default: theatre-daily-snapshot)
    -r, --region REGION        GCP region (default: us-central1)
    -t, --start-time TIME      Daily snapshot time in UTC (default: 04:00)
    -d, --retention DAYS       Snapshot retention in days (default: 7)
    -l, --location LOCATION    Storage location (default: us)
    --disk DISK_NAME           Media disk name (default: theatre-media-disk)
    -h, --help                 Show this help message

Environment Variables:
    GCP_PROJECT_ID             GCP project ID (required)
    GCP_ZONE                   GCP zone where disk is located (required)

Examples:
    $(basename "$0")
    $(basename "$0") --retention 14 --start-time 02:00
    GCP_PROJECT_ID=my-project GCP_ZONE=us-central1-a $(basename "$0")

Note: Requires gcloud CLI to be installed and authenticated.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                SNAPSHOT_SCHEDULE_NAME="$2"
                shift 2
                ;;
            -r|--region)
                SNAPSHOT_REGION="$2"
                shift 2
                ;;
            -t|--start-time)
                SNAPSHOT_START_TIME="$2"
                shift 2
                ;;
            -d|--retention)
                SNAPSHOT_RETENTION_DAYS="$2"
                shift 2
                ;;
            -l|--location)
                SNAPSHOT_STORAGE_LOCATION="$2"
                shift 2
                ;;
            --disk)
                MEDIA_DISK_NAME="$2"
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

# Validate requirements
validate_requirements() {
    if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
        log_error "GCP_PROJECT_ID environment variable is required"
        exit 1
    fi

    if [[ -z "${GCP_ZONE:-}" ]]; then
        log_error "GCP_ZONE environment variable is required"
        exit 1
    fi

    if ! command -v gcloud &>/dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
}

# Create snapshot schedule if it doesn't exist
ensure_snapshot_schedule() {
    log "Checking snapshot schedule ${SNAPSHOT_SCHEDULE_NAME}..."

    if gcloud compute resource-policies describe "${SNAPSHOT_SCHEDULE_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --region="${SNAPSHOT_REGION}" &>/dev/null; then
        log_success "Snapshot schedule ${SNAPSHOT_SCHEDULE_NAME} already exists"
        return 0
    fi

    log "Creating snapshot schedule ${SNAPSHOT_SCHEDULE_NAME}..."
    
    gcloud compute resource-policies create snapshot-schedule "${SNAPSHOT_SCHEDULE_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --region="${SNAPSHOT_REGION}" \
        --description="Daily backup for Theatre media disk" \
        --max-retention-days="${SNAPSHOT_RETENTION_DAYS}" \
        --on-source-disk-delete="apply-retention-policy" \
        --daily-schedule \
        --start-time="${SNAPSHOT_START_TIME}" \
        --storage-location="${SNAPSHOT_STORAGE_LOCATION}"
    
    log_success "Snapshot schedule ${SNAPSHOT_SCHEDULE_NAME} created"
}

# Attach snapshot schedule to disk
attach_schedule_to_disk() {
    log "Checking if schedule is attached to disk ${MEDIA_DISK_NAME}..."

    # Check if disk has this schedule attached
    local attached_schedules
    attached_schedules=$(gcloud compute disks describe "${MEDIA_DISK_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --zone="${GCP_ZONE}" \
        --format="value(resourcePolicies)" 2>/dev/null || echo "")

    if echo "${attached_schedules}" | grep -q "${SNAPSHOT_SCHEDULE_NAME}"; then
        log_success "Snapshot schedule already attached to disk ${MEDIA_DISK_NAME}"
        return 0
    fi

    log "Attaching snapshot schedule to disk ${MEDIA_DISK_NAME}..."
    
    gcloud compute disks add-resource-policies "${MEDIA_DISK_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --zone="${GCP_ZONE}" \
        --resource-policies="${SNAPSHOT_SCHEDULE_NAME}"
    
    log_success "Snapshot schedule attached to disk ${MEDIA_DISK_NAME}"
}

# Print schedule summary
print_summary() {
    log ""
    log "============================================================"
    log "           SNAPSHOT SCHEDULE SUMMARY"
    log "============================================================"
    log "Schedule Name:     ${SNAPSHOT_SCHEDULE_NAME}"
    log "Region:            ${SNAPSHOT_REGION}"
    log "Start Time (UTC):  ${SNAPSHOT_START_TIME}"
    log "Retention Days:    ${SNAPSHOT_RETENTION_DAYS}"
    log "Storage Location:  ${SNAPSHOT_STORAGE_LOCATION}"
    log "Attached Disk:     ${MEDIA_DISK_NAME}"
    log "============================================================"
}

main() {
    parse_args "$@"
    validate_requirements

    ensure_snapshot_schedule
    attach_schedule_to_disk
    print_summary

    log_success "ensure_snapshot_schedule.sh completed"
}

main "$@"
