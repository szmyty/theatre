#!/bin/bash
#
# run_compose.sh - Run docker-compose with all pre-checks
# Part of Theatre project provisioning scripts
#
# This script is an alias for start_compose.sh that ensures
# all prerequisites are met before starting docker-compose.
# It performs pre-flight checks and cleanup before starting containers.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Runs docker-compose with all pre-checks and cleanup.

Options:
    -r, --repo DIR    Repository directory (default: /opt/theatre/repo)
    --no-pull         Skip pulling latest images
    --skip-cleanup    Skip cleanup steps (not recommended)
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
SKIP_CLEANUP=false
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
            --skip-cleanup)
                SKIP_CLEANUP=true
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

# Pre-flight check: verify mounts
check_mounts() {
    log "Checking required mounts..."
    
    # Check media disk mount
    if ! mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        log_error "Media disk not mounted at ${MOUNT_POINT}"
        log_error "Run ensure_disk_mount.sh first"
        exit 1
    fi
    log "Media disk mounted at ${MOUNT_POINT}"
    
    # Check gocryptfs mount (required)
    if ! mountpoint -q "${MOUNT_CLEAR}" 2>/dev/null; then
        log_error "gocryptfs is not mounted at ${MOUNT_CLEAR}"
        log_error "Please ensure gocryptfs is mounted before starting Docker containers"
        log_error "Run: systemctl start gocryptfs-mount.service"
        exit 1
    fi
    log_success "gocryptfs mounted at ${MOUNT_CLEAR}"
}

# Pre-flight check: verify Docker
check_docker() {
    log "Checking Docker..."
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        log_error "Run ensure_docker_installed.sh first"
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        log_error "Docker is not running"
        log_error "Start Docker with: systemctl start docker"
        exit 1
    fi
    
    # Check Docker root
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "UNKNOWN")
    log "Docker root: ${docker_root}"
    
    if [[ "${docker_root}" == "/var/lib/docker" ]]; then
        log_warn "Docker is using root disk, consider running migrate_docker_root.sh"
    fi
}

# Pre-flight check: verify repository
check_repository() {
    log "Checking repository..."
    
    if [[ ! -d "${REPO_DIR}" ]]; then
        log_error "Repository not found at ${REPO_DIR}"
        log_error "Run ensure_repo_clone.sh first"
        exit 1
    fi
    
    if [[ ! -f "${REPO_DIR}/docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in ${REPO_DIR}"
        exit 1
    fi
    
    log "Repository found at ${REPO_DIR}"
}

# Pre-flight check: verify .env file
check_env_file() {
    log "Checking .env file..."
    
    if [[ ! -f "${REPO_DIR}/.env" ]]; then
        log_warn ".env file not found, environment variables may not be set"
    else
        log ".env file exists"
    fi
}

# Run cleanup before compose
run_cleanup() {
    if [[ "${SKIP_CLEANUP}" == "true" ]]; then
        log_warn "Skipping cleanup (--skip-cleanup specified)"
        return 0
    fi
    
    log "Running pre-compose cleanup..."
    
    # Run ensure_jellyfin_clean.sh if available
    if [[ -x "${SCRIPT_DIR}/ensure_jellyfin_clean.sh" ]]; then
        "${SCRIPT_DIR}/ensure_jellyfin_clean.sh" --repo "${REPO_DIR}"
    else
        log_warn "ensure_jellyfin_clean.sh not found or not executable"
        
        # Fallback: basic cleanup
        log "Performing basic cleanup..."
        
        # Remove stale config directory
        if [[ -d "${REPO_DIR}/config/jellyfin" ]]; then
            log "Removing stale config/jellyfin directory..."
            rm -rf "${REPO_DIR}/config/jellyfin"
        fi
        
        # Ensure correct jellyfin config directory
        mkdir -p "${JELLYFIN_CONFIG_DIR}"
        chown -R 1000:1000 "${JELLYFIN_CONFIG_DIR}"
        chmod 755 "${JELLYFIN_CONFIG_DIR}"
    fi
    
    log_success "Pre-compose cleanup completed"
}

# Run docker-compose
run_compose() {
    log "Starting docker-compose..."
    
    cd "${REPO_DIR}" || exit 1
    
    # Pull latest images if requested
    if [[ "${PULL_IMAGES}" == "true" ]]; then
        log "Pulling latest Docker images..."
        docker compose pull
    fi
    
    # Run compose down first to ensure clean state
    log "Running docker compose down..."
    docker compose down --volumes --remove-orphans 2>/dev/null || true
    
    # Start services
    log "Starting services with docker compose up..."
    # Try with --wait flag for health checks (requires Docker Compose v2.1+)
    # If not supported or health checks fail, fall back to basic detached mode
    if docker compose up --detach --wait 2>/dev/null; then
        log_success "Docker services started and healthy"
    else
        # Fallback: start without health check wait (for older Docker Compose versions)
        log "Starting services without health check wait..."
        docker compose up --detach
        log_success "Docker services started (health checks may still be pending)"
    fi
}

# Verify Jellyfin is using correct mount
verify_jellyfin_mount() {
    log "Verifying Jellyfin mount..."
    
    # Wait for container to be ready
    sleep 5
    
    local config_source
    config_source=$(docker inspect jellyfin --format='{{range .Mounts}}{{if eq .Destination "/config"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    
    if [[ "${config_source}" == "${JELLYFIN_CONFIG_DIR}" ]]; then
        log_success "Jellyfin is using correct config mount: ${config_source}"
    else
        log_error "Jellyfin is NOT using correct config mount!"
        log_error "Expected: ${JELLYFIN_CONFIG_DIR}"
        log_error "Actual: ${config_source}"
        log ""
        log "Full mount configuration:"
        docker inspect jellyfin --format='{{json .Mounts}}' 2>/dev/null || echo "Container not found"
        exit 1
    fi
}

main() {
    parse_args "$@"
    require_root
    
    log "=== Pre-flight checks ==="
    check_mounts
    check_docker
    check_repository
    check_env_file
    
    log "=== Cleanup ==="
    run_cleanup
    
    log "=== Starting services ==="
    run_compose
    
    log "=== Verification ==="
    verify_jellyfin_mount
    
    log_success "run_compose.sh completed"
}

main "$@"
