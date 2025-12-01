#!/bin/bash
#
# ensure_vm.sh - Ensure VM is created and running (runs on GitHub Actions runner)
# Part of Theatre project provisioning scripts
#
# This script is designed to be run from GitHub Actions, not on the VM itself.
# It creates the VM if it doesn't exist and ensures it's running.
# It is idempotent - safe to run multiple times.
#

set -euo pipefail

# Colors for output
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions
log() { echo -e "[$(date --iso-8601=seconds)] ${BLUE}INFO${NC}: $*"; }
log_success() { echo -e "[$(date --iso-8601=seconds)] ${GREEN}SUCCESS${NC}: $*"; }
log_warn() { echo -e "[$(date --iso-8601=seconds)] ${YELLOW}WARN${NC}: $*"; }
log_error() { echo -e "[$(date --iso-8601=seconds)] ${RED}ERROR${NC}: $*" >&2; }

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Ensures VM is created and running (for GitHub Actions).

Options:
    --vm-name NAME         VM name (required)
    --project-id ID        GCP project ID (required)
    --zone ZONE            GCP zone (required)
    --machine-type TYPE    Machine type (default: e2-medium)
    --image-family FAMILY  Image family (default: debian-12)
    --image-project PROJ   Image project (default: debian-cloud)
    --boot-disk-size SIZE  Boot disk size (default: 20GB)
    --cloud-init FILE      Cloud-init file path
    -h, --help             Show this help message

Environment Variables:
    VM_NAME                VM name
    GCP_PROJECT_ID         GCP project ID
    GCP_ZONE               GCP zone
    MACHINE_TYPE           Machine type
    IMAGE_FAMILY           Image family
    IMAGE_PROJECT          Image project
    BOOT_DISK_SIZE         Boot disk size
    CLOUD_INIT_FILE        Cloud-init file path

Examples:
    $(basename "$0") --vm-name myvm --project-id myproject --zone us-central1-a
EOF
}

# Default values
MACHINE_TYPE="${MACHINE_TYPE:-e2-medium}"
IMAGE_FAMILY="${IMAGE_FAMILY:-debian-12}"
IMAGE_PROJECT="${IMAGE_PROJECT:-debian-cloud}"
BOOT_DISK_SIZE="${BOOT_DISK_SIZE:-20GB}"
CLOUD_INIT_FILE="${CLOUD_INIT_FILE:-}"

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-name)
                VM_NAME="$2"
                shift 2
                ;;
            --project-id)
                GCP_PROJECT_ID="$2"
                shift 2
                ;;
            --zone)
                GCP_ZONE="$2"
                shift 2
                ;;
            --machine-type)
                MACHINE_TYPE="$2"
                shift 2
                ;;
            --image-family)
                IMAGE_FAMILY="$2"
                shift 2
                ;;
            --image-project)
                IMAGE_PROJECT="$2"
                shift 2
                ;;
            --boot-disk-size)
                BOOT_DISK_SIZE="$2"
                shift 2
                ;;
            --cloud-init)
                CLOUD_INIT_FILE="$2"
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

    # Validate required arguments
    if [[ -z "${VM_NAME:-}" ]]; then
        log_error "VM_NAME is required"
        usage
        exit 1
    fi
    if [[ -z "${GCP_PROJECT_ID:-}" ]]; then
        log_error "GCP_PROJECT_ID is required"
        usage
        exit 1
    fi
    if [[ -z "${GCP_ZONE:-}" ]]; then
        log_error "GCP_ZONE is required"
        usage
        exit 1
    fi
}

# Check if VM exists
vm_exists() {
    gcloud compute instances describe "${VM_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --zone="${GCP_ZONE}" \
        --quiet 2>/dev/null
}

# Create VM
create_vm() {
    log "Creating VM ${VM_NAME}..."

    # Build command arguments
    local -a gcloud_args=(
        "${VM_NAME}"
        "--project=${GCP_PROJECT_ID}"
        "--zone=${GCP_ZONE}"
        "--machine-type=${MACHINE_TYPE}"
        "--image-family=${IMAGE_FAMILY}"
        "--image-project=${IMAGE_PROJECT}"
        "--boot-disk-size=${BOOT_DISK_SIZE}"
        "--tags=http-server,https-server"
    )

    # Add cloud-init if file exists
    if [[ -n "${CLOUD_INIT_FILE}" ]] && [[ -f "${CLOUD_INIT_FILE}" ]]; then
        gcloud_args+=("--metadata-from-file=user-data=${CLOUD_INIT_FILE}")
    fi

    gcloud compute instances create "${gcloud_args[@]}"

    log_success "VM ${VM_NAME} created"
}

# Ensure VM is running
ensure_running() {
    local status
    status=$(gcloud compute instances describe "${VM_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --zone="${GCP_ZONE}" \
        --format="value(status)" 2>/dev/null || echo "UNKNOWN")

    if [[ "${status}" == "RUNNING" ]]; then
        log "VM ${VM_NAME} is already running"
        return 0
    fi

    log "Starting VM ${VM_NAME}..."
    gcloud compute instances start "${VM_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --zone="${GCP_ZONE}"

    # Wait for VM to be ready
    log "Waiting for VM to be ready..."
    for _ in {1..12}; do
        status=$(gcloud compute instances describe "${VM_NAME}" \
            --project="${GCP_PROJECT_ID}" \
            --zone="${GCP_ZONE}" \
            --format="value(status)" 2>/dev/null || echo "UNKNOWN")

        if [[ "${status}" == "RUNNING" ]]; then
            log_success "VM is running"
            return 0
        fi

        log "VM status: ${status}, waiting..."
        sleep 5
    done

    log_error "VM failed to start within timeout"
    exit 1
}

# Get VM external IP
get_external_ip() {
    local ip
    ip=$(gcloud compute instances describe "${VM_NAME}" \
        --project="${GCP_PROJECT_ID}" \
        --zone="${GCP_ZONE}" \
        --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

    echo "${ip}"
}

main() {
    parse_args "$@"

    if vm_exists; then
        log "VM ${VM_NAME} already exists"
    else
        create_vm
    fi

    ensure_running

    local external_ip
    external_ip=$(get_external_ip)
    log_success "VM external IP: ${external_ip}"

    log_success "ensure_vm.sh completed"
}

main "$@"
