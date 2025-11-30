#!/bin/bash
#
# Upload Media Script for Theatre Project
# This script copies a local video file to the remote VM's library directory.
#

set -euo pipefail

# Configuration
REMOTE_DIR="/srv/library_clear"

# Script name for usage display
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Helper function for logging
log() {
    echo "[$(date --iso-8601=seconds)] $*"
}

# Display usage help
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} <local_file> <remote_host>

Copies a local video file to the remote VM's library directory.

Arguments:
    local_file    Path to the local video file to upload
    remote_host   Remote host (e.g., user@hostname or IP address)

Options:
    -h, --help    Show this help message and exit

Examples:
    ${SCRIPT_NAME} /path/to/video.mp4 user@192.168.1.100
    ${SCRIPT_NAME} movie.mkv ubuntu@my-vm.example.com

The file will be copied to ${REMOTE_DIR} on the remote host.
EOF
}

# Validate arguments
validate_args() {
    local local_file="${1:-}"
    local remote_host="${2:-}"

    if [[ -z "${local_file}" ]]; then
        log "ERROR: local_file argument is required"
        echo ""
        usage
        exit 1
    fi

    if [[ -z "${remote_host}" ]]; then
        log "ERROR: remote_host argument is required"
        echo ""
        usage
        exit 1
    fi

    if [[ ! -f "${local_file}" ]]; then
        log "ERROR: File not found: ${local_file}"
        exit 1
    fi

    if [[ ! -r "${local_file}" ]]; then
        log "ERROR: File is not readable: ${local_file}"
        exit 1
    fi
}

# Upload file to remote host
upload_file() {
    local local_file="${1}"
    local remote_host="${2}"
    local filename
    filename="$(basename "${local_file}")"

    log "Uploading '${filename}' to ${remote_host}:${REMOTE_DIR}..."

    scp --compress --preserve "${local_file}" "${remote_host}:${REMOTE_DIR}/"

    log "Upload completed successfully"
}

# Main function
main() {
    # Check for help flag
    if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    local local_file="${1:-}"
    local remote_host="${2:-}"

    validate_args "${local_file}" "${remote_host}"
    upload_file "${local_file}" "${remote_host}"
}

main "$@"
