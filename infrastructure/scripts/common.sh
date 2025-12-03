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

# Discover media disk dynamically via /dev/disk/by-id/
# Searches for Google Cloud persistent disks first, then falls back to
# non-boot disks without partitions.
# Usage: DISK_DEVICE=$(discover_media_disk)
discover_media_disk() {
    local disk_path=""
    local disk_label="${DISK_LABEL:-media}"
    
    # Priority 1: Check for Google Cloud persistent disk by name pattern
    # Google Cloud disks appear as google-<disk-name> in /dev/disk/by-id/
    if [[ -d /dev/disk/by-id ]]; then
        for pattern in "google-${disk_label}" "google-*${disk_label}*"; do
            # Use find to get the first matching symlink (without part suffix)
            disk_path=$(find /dev/disk/by-id -maxdepth 1 -name "${pattern}" ! -name "*-part*" -print -quit 2>/dev/null || true)
            if [[ -n "${disk_path}" && -b "${disk_path}" ]]; then
                echo "${disk_path}"
                return 0
            fi
        done
    fi
    
    # Priority 2: Check for disk by filesystem label
    if [[ -d /dev/disk/by-label ]]; then
        disk_path="/dev/disk/by-label/${disk_label}"
        if [[ -b "${disk_path}" ]]; then
            echo "${disk_path}"
            return 0
        fi
    fi
    
    # Priority 3: Find first non-boot block device without partitions
    # This handles cases where disk IDs are not available
    local boot_disk=""
    boot_disk=$(df / 2>/dev/null | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' || true)
    
    for dev in /dev/sd[b-z] /dev/vd[b-z] /dev/nvme[0-9]n[1-9]; do
        if [[ -b "${dev}" ]]; then
            # Skip the boot disk
            if [[ "${dev}" == "${boot_disk}" ]]; then
                continue
            fi
            # Return the first matching disk
            echo "${dev}"
            return 0
        fi
    done
    
    # Fallback: return empty string if no disk found
    echo ""
    return 1
}

# Common paths used across scripts
MOUNT_POINT="${MOUNT_POINT:-/mnt/disks/media}"
# Use DISK_DEVICE env var if set, otherwise discover dynamically
if [[ -z "${DISK_DEVICE:-}" ]]; then
    DISK_DEVICE=$(discover_media_disk) || DISK_DEVICE=""
fi
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
