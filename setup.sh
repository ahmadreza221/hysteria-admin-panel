#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        print_error "Cannot detect OS"
        exit 1
    fi
}

# Function to install Docker on Ubuntu/Debian
install_docker_ubuntu() {
    print_status "Installing Docker on Ubuntu/Debian..."
    
    # Update package list
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    print_success "Docker installed successfully"
}

# Function to install Docker Compose
install_docker_compose() {
    print_status "Installing Docker Compose..."
    
    # Download Docker Compose
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    
    # Make it executable
    sudo chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker Compose installed successfully"
}

# Function to get domain from user
get_domain() {
    if [[ -n "${DOMAIN:-}" ]]; then
        print_status "Using domain from environment: $DOMAIN"
        return
    fi
    
    echo
    print_status "Please enter your domain name for the Hysteria admin panel:"
    echo "Example: vpn.example.com"
    echo "Leave empty to use localhost (for development)"
    echo
    read -p "Domain name: " DOMAIN
    
    if [[ -z "$DOMAIN" ]]; then
        DOMAIN="localhost"
        print_warning "Using localhost for development"
    else
        print_success "Domain set to: $DOMAIN"
    fi
}

# Function to create environment file
create_env_file() {
    print_status "Creating environment configuration..."
    
    cat > .env << EOF
# Database Configuration
DB_USER=hysteria
DB_PASS=hysteria123
DB_NAME=hysteriadb

# JWT Secret (Change this in production!)
JWT_SECRET=$(openssl rand -hex 32)

# Frontend Configuration
FRONTEND_URL=http://${DOMAIN}:3000
VITE_API_BASE=http://${DOMAIN}:3100/api

# Log Monitor Configuration
HYSTERIA_LOG_PATH=/var/log/hysteria.log

# Domain Configuration
DOMAIN=${DOMAIN}
EOF
    
    print_success "Environment file created"
}

# Function to setup firewall
setup_firewall() {
    print_status "Setting up firewall rules..."
    
    if command -v ufw &> /dev/null; then
        sudo ufw allow 22/tcp
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw allow 3000/tcp
        sudo ufw allow 3100/tcp
        sudo ufw --force enable
        print_success "UFW firewall configured"
    elif command -v iptables &> /dev/null; then
        print_warning "iptables detected. Please manually configure firewall rules:"
        echo "  - Allow ports: 22, 80, 443, 3000, 3100"
    else
        print_warning "No firewall detected. Please configure your firewall manually."
    fi
}

# Function to create log file
create_log_file() {
    print_status "Creating Hysteria log file..."
    
    sudo touch /var/log/hysteria.log
    sudo chmod 644 /var/log/hysteria.log
    
    print_success "Log file created at /var/log/hysteria.log"
}

# Function to start services
start_services() {
    print_status "Starting Hysteria Admin Panel services..."
    
    # Build and start containers
    docker-compose up -d --build
    
    # Wait for services to be ready
    print_status "Waiting for services to start..."
    sleep 30
    
    # Check service health
    if curl -f http://localhost:3100/api/health &> /dev/null; then
        print_success "Backend service is healthy"
    else
        print_warning "Backend service health check failed"
    fi
    
    if curl -f http://localhost:3000/health &> /dev/null; then
        print_success "Frontend service is healthy"
    else
        print_warning "Frontend service health check failed"
    fi
}

# Function to display final information
display_final_info() {
    echo
    echo "=========================================="
    print_success "Hysteria Admin Panel Installation Complete!"
    echo "=========================================="
    echo
    echo "🌐 Admin Panel URL: http://${DOMAIN}:3000"
    echo "🔧 Backend API: http://${DOMAIN}:3100"
    echo "🗄️  Database: localhost:5432"
    echo
    echo "📋 Default Login Credentials:"
    echo "   Email: assiyaee@gmail.com"
    echo "   Username: Admin"
    echo "   Password: Ahmad2016"
    echo
    echo "📁 Important Files:"
    echo "   - Environment: .env"
    echo "   - Logs: /var/log/hysteria.log"
    echo "   - Docker Compose: docker-compose.yml"
    echo
    echo "🔧 Useful Commands:"
    echo "   View logs: docker-compose logs -f"
    echo "   Stop services: docker-compose down"
    echo "   Restart services: docker-compose restart"
    echo "   Update: git pull && docker-compose up -d --build"
    echo
    echo "⚠️  Security Notes:"
    echo "   - Change default passwords in production"
    echo "   - Update JWT_SECRET in .env file"
    echo "   - Configure SSL/TLS for production use"
    echo
    print_success "Installation completed successfully!"
}

# Main installation function
main() {
    echo "=========================================="
    echo "Hysteria v2 Admin Panel Installer"
    echo "=========================================="
    echo
    
    # Check if not running as root
    check_root
    
    # Detect OS
    detect_os
    print_status "Detected OS: $OS $VER"
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_status "Docker not found. Installing..."
        if [[ "$OS" == *"Ubuntu"* ]] || [[ "$OS" == *"Debian"* ]]; then
            install_docker_ubuntu
        else
            print_error "Unsupported OS: $OS"
            print_error "Please install Docker manually and run this script again"
            exit 1
        fi
    else
        print_success "Docker is already installed"
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        print_status "Docker Compose not found. Installing..."
        install_docker_compose
    else
        print_success "Docker Compose is already installed"
    fi
    
    # Get domain from user
    get_domain
    
    # Create environment file
    create_env_file
    
    # Setup firewall
    setup_firewall
    
    # Create log file
    create_log_file
    
    # Start services
    start_services
    
    # Display final information
    display_final_info
}

# Run main function
main "$@"
