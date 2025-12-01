#!/bin/bash
#
# ensure_jellyfin_clean.sh - Clean all stale Jellyfin paths and volumes
# Part of Theatre project provisioning scripts
#
# This script performs thorough cleanup of stale Jellyfin configurations
# including directories, volumes, and containers that may override the
# correct bind mount configuration.
# It is idempotent - safe to run multiple times.
#
# CRITICAL: Run this script BEFORE docker-compose up to ensure
# correct volume mappings are used.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Performs thorough cleanup of stale Jellyfin configurations.

Options:
    -r, --repo DIR    Repository directory (default: /opt/theatre/repo)
    -h, --help        Show this help message

Environment Variables:
    REPO_DIR              Repository directory path
    JELLYFIN_CONFIG_DIR   Jellyfin config directory on media disk

Examples:
    $(basename "$0")
    $(basename "$0") --repo /opt/myrepo
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)
                REPO_DIR="$2"
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

# Remove stale config/jellyfin directory from repo
# Docker ALWAYS prioritizes an existing host directory over a declared volume
remove_stale_config_dir() {
    log "Checking for stale config/jellyfin directories..."
    
    local stale_dirs=(
        "${REPO_DIR}/config/jellyfin"
        "/opt/theatre/repo/config/jellyfin"
    )
    
    for dir in "${stale_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            log "Removing stale directory: ${dir}"
            rm -rf "${dir}"
            log_success "Removed: ${dir}"
        fi
    done
    
    log "No stale config directories found or all removed"
}

# Stop and remove Jellyfin container
remove_jellyfin_container() {
    log "Checking for existing Jellyfin container..."
    
    if docker inspect jellyfin &>/dev/null 2>&1; then
        log "Stopping and removing Jellyfin container..."
        docker stop jellyfin 2>/dev/null || true
        docker rm -f jellyfin 2>/dev/null || true
        log_success "Jellyfin container removed"
    else
        log "No existing Jellyfin container found"
    fi
}

# Remove all stale Jellyfin volumes
# Docker Compose creates implicit volumes with project-name prefixes
remove_stale_volumes() {
    log "Checking for stale volumes..."
    
    local volume_patterns=(
        "jellyfin"
        "repo_jellyfin"
        "theatre_jellyfin"
    )
    
    for pattern in "${volume_patterns[@]}"; do
        local volumes
        volumes=$(docker volume ls --quiet --filter "name=${pattern}" 2>/dev/null || true)
        
        if [[ -n "${volumes}" ]]; then
            log "Found volumes matching '${pattern}':"
            while IFS= read -r vol; do
                if [[ -n "${vol}" ]]; then
                    log "  Removing volume: ${vol}"
                    docker volume rm "${vol}" 2>/dev/null || true
                fi
            done <<< "${volumes}"
        fi
    done
    
    # Also remove volumes by label or name containing config
    local config_volumes
    config_volumes=$(docker volume ls --quiet 2>/dev/null | grep -E '(jellyfin|config)' 2>/dev/null || true)
    
    if [[ -n "${config_volumes}" ]]; then
        log "Found additional config-related volumes:"
        while IFS= read -r vol; do
            if [[ -n "${vol}" ]]; then
                log "  Removing volume: ${vol}"
                docker volume rm "${vol}" 2>/dev/null || true
            fi
        done <<< "${config_volumes}"
    fi
    
    log_success "Stale volumes cleanup completed"
}

# Prune all orphaned volumes
prune_orphan_volumes() {
    log "Pruning orphaned volumes..."
    docker volume prune -f 2>/dev/null || true
    log_success "Orphaned volumes pruned"
}

# Ensure correct Jellyfin config directory exists on media disk
ensure_correct_config_dir() {
    log "Ensuring correct Jellyfin config directory exists at ${JELLYFIN_CONFIG_DIR}..."
    
    if [[ ! -d "${JELLYFIN_CONFIG_DIR}" ]]; then
        log "Creating Jellyfin config directory..."
        mkdir -p "${JELLYFIN_CONFIG_DIR}"
    fi
    
    # Set correct ownership (Jellyfin runs as UID 1000 inside container)
    chown -R 1000:1000 "${JELLYFIN_CONFIG_DIR}"
    chmod 755 "${JELLYFIN_CONFIG_DIR}"
    
    log_success "Jellyfin config directory ready at ${JELLYFIN_CONFIG_DIR}"
}

# Verify no stale configurations remain
verify_cleanup() {
    log "Verifying cleanup..."
    
    local failed=0
    
    # Check for stale directories
    if [[ -d "${REPO_DIR}/config/jellyfin" ]]; then
        log_error "Stale directory still exists: ${REPO_DIR}/config/jellyfin"
        failed=1
    fi
    
    # Check for stale volumes
    local stale_volumes
    stale_volumes=$(docker volume ls --quiet --filter "name=jellyfin" 2>/dev/null || true)
    if [[ -n "${stale_volumes}" ]]; then
        log_warn "Some stale volumes may still exist:"
        echo "${stale_volumes}"
    fi
    
    # Verify correct config directory exists
    if [[ ! -d "${JELLYFIN_CONFIG_DIR}" ]]; then
        log_error "Correct Jellyfin config directory does not exist: ${JELLYFIN_CONFIG_DIR}"
        failed=1
    fi
    
    if [[ ${failed} -eq 1 ]]; then
        log_error "Cleanup verification failed"
        exit 1
    fi
    
    log_success "Cleanup verification passed"
}

main() {
    parse_args "$@"
    require_root
    
    # Docker must be running for volume operations
    if ! docker info &>/dev/null 2>&1; then
        log_warn "Docker is not running, skipping volume cleanup"
    else
        remove_jellyfin_container
        remove_stale_volumes
        prune_orphan_volumes
    fi
    
    remove_stale_config_dir
    ensure_correct_config_dir
    verify_cleanup
    
    log_success "ensure_jellyfin_clean.sh completed"
}

main "$@"
