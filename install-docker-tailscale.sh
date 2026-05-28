#!/bin/bash

# Docker and Tailscale Installation Script
# Supports: Ubuntu, Debian, CentOS, RHEL, Fedora, Rocky Linux, AlmaLinux

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root or with sudo privileges"
        exit 1
    fi
}

# Detect OS distribution
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        print_error "Cannot detect OS distribution"
        exit 1
    fi
}

# Install Docker
install_docker() {
    print_message "Installing Docker..."
    
    case $OS in
        ubuntu|debian)
            # Remove old versions
            apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
            
            # Update package index
            apt-get update
            
            # Install prerequisites
            apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            
            # Add Docker's official GPG key
            mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            # Set up repository
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker Engine
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
            
        centos|rhel|rocky|almalinux|fedora)
            # Remove old versions
            yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
            
            # Install prerequisites
            yum install -y yum-utils
            
            # Add Docker repository
            if [[ $OS == "fedora" ]]; then
                dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            else
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            fi
            
            # Install Docker Engine
            if [[ $OS == "fedora" ]]; then
                dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
            
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_message "Docker installed successfully"
}

# Install Tailscale
install_tailscale() {
    print_message "Installing Tailscale..."
    
    case $OS in
        ubuntu|debian)
            curl -fsSL https://pkgs.tailscale.com/stable/$OS/$(lsb_release -cs).noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
            curl -fsSL https://pkgs.tailscale.com/stable/$OS/$(lsb_release -cs).tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list
            apt-get update
            apt-get install -y tailscale
            ;;
            
        centos|rhel|rocky|almalinux|fedora)
            if [[ $OS == "fedora" ]]; then
                dnf install -y 'dnf-command(config-manager)'
                dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo
                dnf install -y tailscale
            else
                yum install -y yum-utils
                yum-config-manager --add-repo https://pkgs.tailscale.com/stable/centos/tailscale.repo
                yum install -y tailscale
            fi
            ;;
            
        *)
            print_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac
    
    # Start and enable Tailscale
    systemctl start tailscaled
    systemctl enable tailscaled
    
    print_message "Tailscale installed successfully"
}

# Configure Docker to work without sudo (optional)
configure_docker_sudo() {
    print_message "Would you like to add the current user to the docker group? (y/n)"
    read -r response
    if [[ $response == "y" || $response == "Y" ]]; then
        if [[ -n "$SUDO_USER" ]]; then
            usermod -aG docker "$SUDO_USER"
            print_message "User $SUDO_USER added to docker group. You may need to log out and back in for changes to take effect."
        else
            print_warning "Could not detect sudo user. Please manually add users to docker group if needed."
        fi
    fi
}

# Setup Tailscale authentication
setup_tailscale_auth() {
    print_message "Do you want to authenticate Tailscale now? (y/n)"
    read -r response
    if [[ $response == "y" || $response == "Y" ]]; then
        print_message "Please visit the URL shown below to authenticate Tailscale..."
        tailscale up
    else
        print_message "You can authenticate Tailscale later by running: tailscale up"
    fi
}

# Verify installations
verify_installations() {
    print_message "Verifying installations..."
    
    # Verify Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        print_message "✓ Docker installed: $DOCKER_VERSION"
    else
        print_error "✗ Docker installation failed"
        exit 1
    fi
    
    # Verify Docker Compose
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version)
        print_message "✓ Docker Compose installed: $COMPOSE_VERSION"
    fi
    
    # Verify Tailscale
    if command -v tailscale &> /dev/null; then
        TAILSCALE_VERSION=$(tailscale version)
        print_message "✓ Tailscale installed: $TAILSCALE_VERSION"
    else
        print_error "✗ Tailscale installation failed"
        exit 1
    fi
}

# Main execution
main() {
    print_message "Starting Docker and Tailscale installation..."
    print_message "=============================================="
    
    check_root
    detect_os
    
    print_message "Detected OS: $OS $VERSION"
    
    # Install Docker
    install_docker
    
    # Install Tailscale
    install_tailscale
    
    # Verify installations
    verify_installations
    
    # Optional configurations
    configure_docker_sudo
    setup_tailscale_auth
    
    print_message "=============================================="
    print_message "Installation completed successfully!"
    print_message "Useful commands:"
    print_message "  - Check Docker status: systemctl status docker"
    print_message "  - Check Tailscale status: systemctl status tailscaled"
    print_message "  - Tailscale authentication: tailscale up"
    print_message "  - List Tailscale devices: tailscale status"
    print_message "  - Test Docker: docker run hello-world"
}

# Run main function
main