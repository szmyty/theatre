#!/bin/bash
#
# diagnostics.sh - Collect and display system diagnostics
# Part of Theatre project provisioning scripts
#
# This script collects diagnostic information for troubleshooting.
# It is idempotent - safe to run multiple times.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Display usage help
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Collects and displays system diagnostics for troubleshooting.

Options:
    --full           Include full container logs
    -h, --help       Show this help message

Examples:
    $(basename "$0")
    $(basename "$0") --full
EOF
}

# Parse command line arguments
FULL_LOGS=false
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --full)
                FULL_LOGS=true
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

# Print section header
section() {
    echo ""
    echo "============================================================"
    echo "  $1"
    echo "============================================================"
    echo ""
}

# System information
print_system_info() {
    section "SYSTEM INFORMATION"

    echo "Hostname: $(hostname)"
    echo "Date: $(date)"
    echo "Kernel: $(uname -r)"
    echo ""

    echo "Memory:"
    free -h
    echo ""

    echo "Disk usage:"
    df -h
    echo ""
}

# Mount information
print_mount_info() {
    section "MOUNT INFORMATION"

    echo "Media disk mount (${MOUNT_POINT}):"
    if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
        echo "  Status: MOUNTED"
        df -h "${MOUNT_POINT}" 2>/dev/null | tail -1
    else
        echo "  Status: NOT MOUNTED"
    fi
    echo ""

    echo "gocryptfs mount (${MOUNT_CLEAR}):"
    if mountpoint -q "${MOUNT_CLEAR}" 2>/dev/null; then
        echo "  Status: MOUNTED"
    else
        echo "  Status: NOT MOUNTED"
    fi
    echo ""

    echo "All mounts:"
    mount | grep -E "(${MOUNT_POINT}|${MOUNT_CLEAR}|/dev/sd)" || echo "  No relevant mounts found"
    echo ""
}

# Docker information
print_docker_info() {
    section "DOCKER INFORMATION"

    if ! command -v docker &>/dev/null; then
        echo "Docker is NOT installed"
        return
    fi

    echo "Docker version:"
    docker --version
    echo ""

    echo "Docker root directory:"
    docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "Unable to determine"
    echo ""

    echo "containerd root:"
    grep -E '^\s*root\s*=' /etc/containerd/config.toml 2>/dev/null | head -1 || echo "Unable to determine"
    echo ""

    echo "Docker disk usage:"
    docker system df 2>/dev/null || echo "Unable to determine"
    echo ""
}

# Container information
print_container_info() {
    section "CONTAINER INFORMATION"

    if ! command -v docker &>/dev/null; then
        echo "Docker is NOT installed"
        return
    fi

    echo "Running containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "No containers running"
    echo ""

    echo "All containers:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>/dev/null || echo "No containers found"
    echo ""

    # Jellyfin details
    if docker inspect jellyfin &>/dev/null; then
        echo "Jellyfin container mounts:"
        docker inspect jellyfin --format='{{range .Mounts}}  {{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null | sed '/^$/d'
        echo ""
    fi

    # Container logs
    if [[ "${FULL_LOGS}" == "true" ]]; then
        echo "Jellyfin logs:"
        docker logs --tail 50 jellyfin 2>&1 || echo "No logs available"
        echo ""

        echo "Caddy logs:"
        docker logs --tail 50 caddy 2>&1 || echo "No logs available"
        echo ""
    fi
}

# Service information
print_service_info() {
    section "SYSTEMD SERVICES"

    echo "Docker service:"
    systemctl is-active docker 2>/dev/null || echo "inactive"
    echo ""

    echo "containerd service:"
    systemctl is-active containerd 2>/dev/null || echo "inactive"
    echo ""

    echo "gocryptfs-mount service:"
    systemctl is-active gocryptfs-mount 2>/dev/null || echo "inactive"
    echo ""

    echo "duckdns-update timer:"
    systemctl is-active duckdns-update.timer 2>/dev/null || echo "inactive"
    echo ""
}

# Network information
print_network_info() {
    section "NETWORK INFORMATION"

    echo "Listening ports:"
    ss -tlnp 2>/dev/null | grep -E ':(80|443|8096)' || echo "No relevant ports listening"
    echo ""

    echo "Public IP (via DuckDNS):"
    curl -s https://api.ipify.org 2>/dev/null || echo "Unable to determine"
    echo ""
}

# Environment files
print_env_info() {
    section "ENVIRONMENT FILES"

    echo ".env file (${REPO_DIR}/.env):"
    if [[ -f "${REPO_DIR}/.env" ]]; then
        # Show non-sensitive parts only
        grep -v -E "(TOKEN|PASSWORD|SECRET)" "${REPO_DIR}/.env" 2>/dev/null || cat "${REPO_DIR}/.env"
        echo "  (sensitive values hidden)"
    else
        echo "  NOT FOUND"
    fi
    echo ""

    echo "gocryptfs.env:"
    if [[ -f "${GOCRYPTFS_ENV_DIR}/gocryptfs.env" ]]; then
        cat "${GOCRYPTFS_ENV_DIR}/gocryptfs.env" 2>/dev/null || echo "  Unable to read"
    else
        echo "  NOT FOUND"
    fi
    echo ""
}

main() {
    parse_args "$@"

    log "Collecting diagnostics..."

    print_system_info
    print_mount_info
    print_docker_info
    print_container_info
    print_service_info
    print_network_info
    print_env_info

    section "DIAGNOSTICS COMPLETE"

    log_success "diagnostics.sh completed"
}

main "$@"
