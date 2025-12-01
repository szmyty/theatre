#!/bin/bash
#
# Common utility functions for Theatre provisioning scripts
# This file is sourced by other scripts and should not be executed directly.
#

# Exit on error, undefined variables, and pipe failures
set -euo pipefail

# Colors for output (if terminal supports it)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Logging functions with consistent format
log() {
    echo -e "[$(date --iso-8601=seconds)] ${BLUE}INFO${NC}: $*"
}

log_success() {
    echo -e "[$(date --iso-8601=seconds)] ${GREEN}SUCCESS${NC}: $*"
}

log_warn() {
    echo -e "[$(date --iso-8601=seconds)] ${YELLOW}WARN${NC}: $*"
}

log_error() {
    echo -e "[$(date --iso-8601=seconds)] ${RED}ERROR${NC}: $*" >&2
}

# Check if running as root
require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Common paths used across scripts
MOUNT_POINT="${MOUNT_POINT:-/mnt/disks/media}"
DISK_DEVICE="${DISK_DEVICE:-/dev/sdb}"
REPO_DIR="${REPO_DIR:-/opt/theatre/repo}"
REPO_URL="${REPO_URL:-https://github.com/szmyty/theatre.git}"

# Docker data paths
DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-${MOUNT_POINT}/docker}"
CONTAINERD_DATA_ROOT="${CONTAINERD_DATA_ROOT:-${MOUNT_POINT}/containerd}"

# gocryptfs paths
ENCRYPTED_DIR="${ENCRYPTED_DIR:-${MOUNT_POINT}/.library_encrypted}"
MOUNT_CLEAR="${MOUNT_CLEAR:-/srv/library_clear}"
GOCRYPTFS_ENV_DIR="${GOCRYPTFS_ENV_DIR:-/etc/gocryptfs}"
GOCRYPTFS_PASSFILE="${GOCRYPTFS_PASSFILE:-${GOCRYPTFS_ENV_DIR}/passfile}"

# Jellyfin paths
JELLYFIN_CONFIG_DIR="${JELLYFIN_CONFIG_DIR:-${MOUNT_POINT}/jellyfin_config}"

# DuckDNS paths
DUCKDNS_ENV_DIR="${DUCKDNS_ENV_DIR:-/etc/duckdns}"
