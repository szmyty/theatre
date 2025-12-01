#!/bin/bash
#
# ensure_repo_clone.sh - Clone or update the theatre repository
# Part of Theatre project provisioning scripts
#
# This script clones the repository if not present, or updates it
# if already cloned. It also removes stale directories.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Clones or updates the theatre repository.

Options:
    -r, --repo URL         Repository URL (default: https://github.com/szmyty/theatre.git)
    -d, --dir PATH         Target directory (default: /opt/theatre/repo)
    -h, --help             Show this help message

Environment Variables:
    REPO_URL               Override repository URL
    REPO_DIR               Override target directory

Examples:
    $(basename "$0")
    $(basename "$0") --repo https://github.com/user/repo.git --dir /opt/myrepo
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)
                REPO_URL="$2"
                shift 2
                ;;
            -d|--dir)
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

# Clone or update repository
clone_or_update_repo() {
    log "Checking repository at ${REPO_DIR}..."

    if [[ ! -d "${REPO_DIR}" ]]; then
        log "Cloning repository from ${REPO_URL}..."
        mkdir -p "$(dirname "${REPO_DIR}")"
        git clone --depth 1 "${REPO_URL}" "${REPO_DIR}"
        log_success "Repository cloned"
    else
        log "Updating repository in ${REPO_DIR}..."
        cd "${REPO_DIR}" || exit 1
        git fetch --depth 1 origin
        git reset --hard origin/HEAD
        log_success "Repository updated"
    fi
}

# Remove stale config/jellyfin directory
# Docker ALWAYS prioritizes an existing host directory over a declared volume,
# which completely overrides our intended volume mapping.
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

# Ensure Jellyfin config directory exists on media disk
ensure_jellyfin_config() {
    log "Ensuring Jellyfin config directory ${JELLYFIN_CONFIG_DIR} exists..."
    mkdir -p "${JELLYFIN_CONFIG_DIR}"
    chown -R 1000:1000 "${JELLYFIN_CONFIG_DIR}"
    chmod 755 "${JELLYFIN_CONFIG_DIR}"
    log_success "Jellyfin config directory ready"
}

main() {
    parse_args "$@"
    require_root

    clone_or_update_repo
    remove_stale_config
    ensure_jellyfin_config

    log_success "ensure_repo_clone.sh completed"
}

main "$@"
