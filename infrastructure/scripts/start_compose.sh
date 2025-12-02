#!/bin/bash
#
# start_compose.sh - Start Docker Compose services
# Part of Theatre project provisioning scripts
#
# This script starts the Docker Compose services after pulling
# the latest images. It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Starts Docker Compose services.

Options:
    -r, --repo DIR    Repository directory (default: /opt/theatre/repo)
    --no-pull         Skip pulling latest images
    -h, --help        Show this help message

Environment Variables:
    REPO_DIR          Repository directory path

Examples:
    $(basename "$0")
    $(basename "$0") --repo /opt/myrepo
    $(basename "$0") --no-pull
EOF
}

# Parse command line arguments
PULL_IMAGES=true
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--repo)
                REPO_DIR="$2"
                shift 2
                ;;
            --no-pull)
                PULL_IMAGES=false
                shift
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

# Pull latest images
pull_images() {
    if [[ "${PULL_IMAGES}" != "true" ]]; then
        log "Skipping image pull (--no-pull specified)"
        return 0
    fi

    log "Pulling latest Docker images..."
    docker compose pull
    log_success "Images pulled"
}

# Verify gocryptfs mount is ready before starting containers
verify_gocryptfs_mount() {
    log "Verifying gocryptfs mount is ready..."

    if ! mountpoint -q "${MOUNT_CLEAR}"; then
        log_error "gocryptfs is not mounted at ${MOUNT_CLEAR}"
        log_error "Please ensure gocryptfs is mounted before starting Docker containers"
        log_error "Run: systemctl start gocryptfs-mount.service"
        return 1
    fi

    log_success "gocryptfs is mounted at ${MOUNT_CLEAR}"
    return 0
}

# Start services
start_services() {
    log "Starting docker-compose services..."

    # Try with --wait first for health checks
    if docker compose up --detach --wait 2>/dev/null; then
        log_success "Docker services started and healthy"
    else
        # Fallback: start without waiting for health checks
        log "Starting services without health check wait..."
        docker compose up --detach
        log_success "Docker services started (health checks may still be pending)"
    fi
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    sleep 5

    # Check jellyfin container
    local jellyfin_status
    jellyfin_status=$(docker inspect --format='{{.State.Status}}' jellyfin 2>/dev/null || echo "not_found")

    if [[ "${jellyfin_status}" == "running" ]]; then
        log_success "Jellyfin container is running"
    else
        log_warn "Jellyfin container status: ${jellyfin_status}"
    fi

    # Check caddy container
    local caddy_status
    caddy_status=$(docker inspect --format='{{.State.Status}}' caddy 2>/dev/null || echo "not_found")

    if [[ "${caddy_status}" == "running" ]]; then
        log_success "Caddy container is running"
    else
        log_warn "Caddy container status: ${caddy_status}"
    fi
}

main() {
    parse_args "$@"
    require_root

    if [[ ! -d "${REPO_DIR}" ]]; then
        log_error "Repository directory not found at ${REPO_DIR}"
        log_error "Run ensure_repo_clone.sh first"
        exit 1
    fi

    cd "${REPO_DIR}" || exit 1

    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in ${REPO_DIR}"
        exit 1
    fi

    # Verify gocryptfs mount before starting containers
    if ! verify_gocryptfs_mount; then
        log_error "Cannot start docker-compose without gocryptfs mount"
        exit 1
    fi

    pull_images
    start_services
    wait_for_services

    log_success "start_compose.sh completed"
}

main "$@"
