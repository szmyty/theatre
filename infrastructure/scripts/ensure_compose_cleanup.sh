#!/bin/bash
#
# ensure_compose_cleanup.sh - Clean up Docker before compose
# Part of Theatre project provisioning scripts
#
# This script performs Docker cleanup to remove stale containers,
# volumes, and orphans before starting docker-compose.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Performs Docker cleanup before starting docker-compose.

Options:
    -r, --repo DIR    Repository directory (default: /opt/theatre/repo)
    -h, --help        Show this help message

Environment Variables:
    REPO_DIR          Repository directory path

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

# Stop and remove containers with docker-compose
compose_down() {
    log "Running docker compose down..."
    cd "${REPO_DIR}" || exit 1
    docker compose down --volumes --remove-orphans 2>/dev/null || true
    log_success "docker compose down completed"
}

# Remove jellyfin container specifically
remove_jellyfin_container() {
    log "Removing jellyfin container if exists..."
    docker rm -f jellyfin 2>/dev/null || true
}

# Prune unused volumes
prune_volumes() {
    log "Pruning unused volumes..."
    docker volume prune -f 2>/dev/null || true
}

# Remove stale jellyfin volumes
remove_jellyfin_volumes() {
    log "Checking for stale jellyfin volumes..."

    local stale_volumes
    stale_volumes=$(docker volume ls --quiet --filter "name=jellyfin" 2>/dev/null || true)

    if [[ -n "${stale_volumes}" ]]; then
        log "Found stale jellyfin volumes, removing..."
        while IFS= read -r vol; do
            if [[ -n "${vol}" ]]; then
                log "Removing volume: ${vol}"
                docker volume rm "${vol}" 2>/dev/null || true
            fi
        done <<< "${stale_volumes}"
        log_success "Stale jellyfin volumes removed"
    else
        log "No stale jellyfin volumes found"
    fi
}

# Remove stale config/jellyfin directory from repo
remove_stale_config() {
    log "Checking for stale config/jellyfin directory..."

    local stale_dir="${REPO_DIR}/config/jellyfin"

    if [[ -d "${stale_dir}" ]]; then
        log "Removing stale config/jellyfin directory..."
        rm -rf "${stale_dir}"
        log_success "Stale directory removed"
    else
        log "No stale config/jellyfin directory found"
    fi
}

# Ensure correct Jellyfin config directory exists on media disk
ensure_jellyfin_config() {
    log "Ensuring correct Jellyfin config directory exists..."
    mkdir -p "${JELLYFIN_CONFIG_DIR}"
    chown -R 1000:1000 "${JELLYFIN_CONFIG_DIR}"
    chmod 755 "${JELLYFIN_CONFIG_DIR}"
    log_success "Jellyfin config directory ready at ${JELLYFIN_CONFIG_DIR}"
}

main() {
    parse_args "$@"
    require_root

    if [[ ! -d "${REPO_DIR}" ]]; then
        log_error "Repository directory not found at ${REPO_DIR}"
        log_error "Run ensure_repo_clone.sh first"
        exit 1
    fi

    compose_down
    remove_jellyfin_container
    prune_volumes
    remove_jellyfin_volumes
    remove_stale_config
    ensure_jellyfin_config

    log_success "ensure_compose_cleanup.sh completed"
}

main "$@"
