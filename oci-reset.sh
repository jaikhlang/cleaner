#!/bin/bash

# OCI Instance Reset Script
# Preserves: Docker, Tailscale
# Removes: Dokploy, Traefik, PostgreSQL, Redis (containers, images, volumes, networks, configs)

set -e  # Exit on error
set -u  # Exit on undefined variable

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/oci_reset_$(date +%Y%m%d_%H%M%S).log"

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to confirm action (for safety)
confirm_reset() {
    log_message "${YELLOW}WARNING: This script will remove all Dokploy, Traefik, PostgreSQL, and Redis components.${NC}"
    log_message "${YELLOW}Docker and Tailscale will be preserved.${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_message "${RED}Reset cancelled by user.${NC}"
        exit 1
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_message "${RED}This script must be run as root. Use: sudo bash $0${NC}"
   exit 1
fi

# Main reset function
reset_oci_instance() {
    log_message "${GREEN}Starting OCI instance reset...${NC}"
    log_message "Log file: $LOG_FILE"

    # Check for Docker
    if ! command_exists docker; then
        log_message "${RED}Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi

    log_message "${GREEN}Docker found. Proceeding with cleanup...${NC}"

    # 1. Stop all containers related to dokploy, traefik, postgres, redis
    log_message "${YELLOW}Stopping containers...${NC}"
    CONTAINERS_TO_STOP=$(docker ps -a --filter "name=dokploy" --filter "name=traefik" --filter "name=postgres" --filter "name=redis" -q)
    if [[ -n "$CONTAINERS_TO_STOP" ]]; then
        docker stop $CONTAINERS_TO_STOP 2>/dev/null || true
        docker rm $CONTAINERS_TO_STOP 2>/dev/null || true
        log_message "${GREEN}Containers stopped and removed.${NC}"
    else
        log_message "No matching containers found."
    fi

    # Also stop containers with these labels or images
    CONTAINERS_BY_IMAGE=$(docker ps -a --filter "ancestor=dokploy" --filter "ancestor=traefik" --filter "ancestor=postgres" --filter "ancestor=redis" -q)
    if [[ -n "$CONTAINERS_BY_IMAGE" ]]; then
        docker stop $CONTAINERS_BY_IMAGE 2>/dev/null || true
        docker rm $CONTAINERS_BY_IMAGE 2>/dev/null || true
        log_message "${GREEN}Additional containers removed.${NC}"
    fi

    # 2. Remove Docker images
    log_message "${YELLOW}Removing Docker images...${NC}"
    IMAGES_TO_REMOVE=$(docker images --filter "reference=dokploy*" --filter "reference=traefik*" --filter "reference=postgres*" --filter "reference=redis*" -q)
    if [[ -n "$IMAGES_TO_REMOVE" ]]; then
        docker rmi -f $IMAGES_TO_REMOVE 2>/dev/null || true
        log_message "${GREEN}Images removed.${NC}"
    else
        log_message "No matching images found."
    fi

    # 3. Remove Docker volumes
    log_message "${YELLOW}Removing Docker volumes...${NC}"
    VOLUMES_TO_REMOVE=$(docker volume ls --filter "name=dokploy" --filter "name=postgres" --filter "name=redis" --filter "name=traefik" -q)
    if [[ -n "$VOLUMES_TO_REMOVE" ]]; then
        docker volume rm $VOLUMES_TO_REMOVE 2>/dev/null || true
        log_message "${GREEN}Volumes removed.${NC}"
    else
        log_message "No matching volumes found."
    fi

    # Also remove orphaned volumes
    docker volume prune -f 2>/dev/null || true

    # 4. Remove Docker networks
    log_message "${YELLOW}Removing Docker networks...${NC}"
    NETWORKS_TO_REMOVE=$(docker network ls --filter "name=dokploy" --filter "name=traefik" --filter "name=postgres" --filter "name=redis" -q)
    if [[ -n "$NETWORKS_TO_REMOVE" ]]; then
        docker network rm $NETWORKS_TO_REMOVE 2>/dev/null || true
        log_message "${GREEN}Networks removed.${NC}"
    else
        log_message "No matching networks found."
    fi

    # 5. Clean up system (dangling images, containers, networks)
    log_message "${YELLOW}Performing Docker system prune...${NC}"
    docker system prune -a -f --volumes 2>/dev/null || true
    log_message "${GREEN}Docker system cleaned.${NC}"

    # 6. Remove configuration directories
    log_message "${YELLOW}Removing configuration directories...${NC}"
    CONFIG_DIRS=(
        "/etc/dokploy"
        "/var/lib/dokploy"
        "/opt/dokploy"
        "/etc/traefik"
        "/var/lib/traefik"
        "/etc/postgresql"
        "/var/lib/postgresql"
        "/etc/redis"
        "/var/lib/redis"
        "/var/log/dokploy"
        "/var/log/traefik"
        "/var/log/postgresql"
        "/var/log/redis"
    )

    for dir in "${CONFIG_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir" 2>/dev/null || true
            log_message "Removed $dir"
        fi
    done

    # 7. Clean system logs
    log_message "${YELLOW}Cleaning system logs...${NC}"
    
    # Clear journal logs (keep last 7 days)
    if command_exists journalctl; then
        journalctl --vacuum-time=7d 2>/dev/null || true
        log_message "Journal logs cleaned (kept last 7 days)"
    fi
    
    # Clear old log files
    find /var/log -type f -name "*.log" -mtime +30 -delete 2>/dev/null || true
    find /var/log -type f -name "dokploy*.log" -delete 2>/dev/null || true
    find /var/log -type f -name "traefik*.log" -delete 2>/dev/null || true
    find /var/log -type f -name "postgres*.log" -delete 2>/dev/null || true
    find /var/log -type f -name "redis*.log" -delete 2>/dev/null || true
    
    # Truncate existing log files
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    
    log_message "${GREEN}Logs cleaned.${NC}"

    # 8. Remove temporary files
    log_message "${YELLOW}Cleaning temporary files...${NC}"
    rm -rf /tmp/dokploy* 2>/dev/null || true
    rm -rf /tmp/traefik* 2>/dev/null || true
    rm -rf /tmp/postgres* 2>/dev/null || true
    rm -rf /tmp/redis* 2>/dev/null || true
    rm -rf /var/tmp/dokploy* 2>/dev/null || true
    rm -rf /var/tmp/traefik* 2>/dev/null || true
    
    # Clean temp files older than 7 days
    find /tmp -type f -atime +7 -delete 2>/dev/null || true
    find /var/tmp -type f -atime +7 -delete 2>/dev/null || true

    # 9. Check and preserve Tailscale
    log_message "${YELLOW}Checking Tailscale status...${NC}"
    if command_exists tailscale; then
        TAILSCALE_STATUS=$(tailscale status 2>/dev/null || echo "not connected")
        log_message "${GREEN}Tailscale found. Status: $TAILSCALE_STATUS${NC}"
    else
        log_message "Tailscale not installed or not in PATH"
    fi

    # 10. Docker service status
    log_message "${YELLOW}Checking Docker service...${NC}"
    if systemctl is-active --quiet docker; then
        log_message "${GREEN}Docker service is running.${NC}"
    else
        log_message "${YELLOW}Docker service is not running. Starting it...${NC}"
        systemctl start docker
    fi

    # 11. Disk cleanup after reset
    log_message "${YELLOW}Performing final disk cleanup...${NC}"
    
    # Clean package manager cache
    if command_exists apt-get; then
        apt-get clean 2>/dev/null || true
        apt-get autoclean 2>/dev/null || true
    elif command_exists yum; then
        yum clean all 2>/dev/null || true
    elif command_exists dnf; then
        dnf clean all 2>/dev/null || true
    fi
    
    # Remove old kernel headers (optional, safe)
    if command_exists apt-get; then
        apt-get autoremove -y 2>/dev/null || true
    fi
    
    # Display disk usage after cleanup
    log_message "${GREEN}Disk usage after cleanup:${NC}"
    df -h / | tail -1 | tee -a "$LOG_FILE"

    log_message "${GREEN}========================================${NC}"
    log_message "${GREEN}OCI Instance Reset Complete!${NC}"
    log_message "${GREEN}========================================${NC}"
    log_message "Docker and Tailscale preserved"
    log_message "All Dokploy, Traefik, PostgreSQL, Redis components removed"
    log_message "Logs cleaned up"
    log_message "System ready for fresh installations"
    log_message "Log saved to: $LOG_FILE"
}

# Safety confirmation
confirm_reset

# Execute reset
reset_oci_instance

# Optional: Offer reboot
read -p "Would you like to reboot the system now? (recommended) (yes/no): " -r
echo
if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_message "${YELLOW}Rebooting system...${NC}"
    reboot
else
    log_message "${GREEN}Reset completed. You may want to reboot manually later.${NC}"
fi