#!/bin/bash

# NetAlertX Installation Script for LXC Container
# This script is executed inside the LXC container to install and configure NetAlertX
# Supports both development and production deployments

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
NETALERTX_VERSION="latest"
NETALERTX_PORT="20211"
GRAPHQL_PORT="20212"
TIMEZONE="UTC"
PUID="1000"
PGID="1000"
DEPLOYMENT_TYPE="development"
DATA_DIR="/opt/netalertx"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"

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
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    apt-get update
    apt-get upgrade -y
    
    print_status "Installing essential packages..."
    apt-get install -y \
        curl \
        wget \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        ufw \
        htop \
        nano \
        net-tools \
        iputils-ping
    
    print_success "System updated successfully"
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    # Remove any old Docker installations
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable and start Docker
    systemctl enable docker
    systemctl start docker
    
    # Add user to docker group if it exists
    if id "netalertx" &>/dev/null; then
        usermod -aG docker netalertx
    fi
    
    # Verify Docker installation
    if docker --version && docker compose version; then
        print_success "Docker installed successfully"
    else
        print_error "Docker installation failed"
        exit 1
    fi
}

# Function to create NetAlertX user and directories
setup_netalertx_user() {
    print_status "Setting up NetAlertX user and directories..."
    
    # Create netalertx user if it doesn't exist
    if ! id "netalertx" &>/dev/null; then
        useradd -r -s /bin/bash -m -d /home/netalertx netalertx
        usermod -aG docker netalertx
        print_success "Created netalertx user"
    fi
    
    # Create directory structure
    mkdir -p $DATA_DIR/{config,db,logs,backups}
    
    # Set ownership
    chown -R netalertx:netalertx $DATA_DIR
    chmod 755 $DATA_DIR
    chmod 755 $DATA_DIR/{config,db,logs,backups}
    
    print_success "NetAlertX directories created"
}

# Function to create Docker Compose configuration
create_docker_compose() {
    print_status "Creating Docker Compose configuration..."
    
    # Determine timezone
    if [ -f /etc/timezone ]; then
        TIMEZONE=$(cat /etc/timezone)
    elif [ -L /etc/localtime ]; then
        TIMEZONE=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
    fi
    
    # Create docker-compose.yml based on deployment type
    if [ "$DEPLOYMENT_TYPE" = "production" ]; then
        create_production_compose
    else
        create_development_compose
    fi
    
    print_success "Docker Compose configuration created"
}

# Function to create development Docker Compose
create_development_compose() {
    cat > $COMPOSE_FILE << EOF
version: '3.8'

services:
  netalertx:
    image: ghcr.io/jokob-sk/netalertx:${NETALERTX_VERSION}
    container_name: netalertx
    network_mode: host
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    volumes:
      - ${DATA_DIR}/config:/app/config
      - ${DATA_DIR}/db:/app/db
      - ${DATA_DIR}/logs:/app/log
    tmpfs:
      - /app/api:size=100M,uid=${PUID},gid=${PGID}
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TIMEZONE}
      - PORT=${NETALERTX_PORT}
      - LISTEN_ADDR=0.0.0.0
      - GRAPHQL_PORT=${GRAPHQL_PORT}
    cap_add:
      - NET_ADMIN
      - NET_RAW
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
}

# Function to create production Docker Compose
create_production_compose() {
    cat > $COMPOSE_FILE << EOF
version: '3.8'

services:
  netalertx:
    image: ghcr.io/jokob-sk/netalertx:${NETALERTX_VERSION}
    container_name: netalertx
    network_mode: host
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    volumes:
      - ${DATA_DIR}/config:/app/config
      - ${DATA_DIR}/db:/app/db
      - ${DATA_DIR}/logs:/app/log
      - ${DATA_DIR}/backups:/app/backups
    tmpfs:
      - /app/api:size=200M,uid=${PUID},gid=${PGID}
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TIMEZONE}
      - PORT=${NETALERTX_PORT}
      - LISTEN_ADDR=0.0.0.0
      - GRAPHQL_PORT=${GRAPHQL_PORT}
      # Additional production settings
      - LOADED_PLUGINS=["ARPSCAN","PIHOLE"]
    cap_add:
      - NET_ADMIN
      - NET_RAW
    security_opt:
      - no-new-privileges:true
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "5"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${NETALERTX_PORT}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

# Function to setup systemd service
setup_systemd_service() {
    print_status "Setting up systemd service..."
    
    cat > /etc/systemd/system/netalertx.service << EOF
[Unit]
Description=NetAlertX Network Scanner
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${DATA_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0
User=netalertx
Group=netalertx

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable netalertx.service
    
    print_success "Systemd service configured"
}

# Function to configure firewall
configure_firewall() {
    print_status "Configuring firewall..."
    
    # Enable UFW
    ufw --force enable
    
    # Allow SSH
    ufw allow ssh
    
    # Allow NetAlertX ports
    ufw allow $NETALERTX_PORT/tcp
    ufw allow $GRAPHQL_PORT/tcp
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    print_success "Firewall configured"
}

# Function to create management scripts
create_management_scripts() {
    print_status "Creating management scripts..."
    
    # Update script
    cat > /usr/local/bin/netalertx-update << 'EOF'
#!/bin/bash
# NetAlertX Update Script

DATA_DIR="/opt/netalertx"

echo "Stopping NetAlertX..."
cd $DATA_DIR
docker compose down

echo "Backing up current state..."
mkdir -p backups
tar -czf backups/netalertx-backup-$(date +%Y%m%d_%H%M%S).tar.gz config/ db/

echo "Pulling latest images..."
docker compose pull

echo "Starting NetAlertX..."
docker compose up -d

echo "Cleaning up old images..."
docker image prune -f

echo "NetAlertX updated successfully!"
EOF
    
    # Backup script
    cat > /usr/local/bin/netalertx-backup << 'EOF'
#!/bin/bash
# NetAlertX Backup Script

DATA_DIR="/opt/netalertx"
BACKUP_DIR="$DATA_DIR/backups"
BACKUP_NAME="netalertx-backup-$(date +%Y%m%d_%H%M%S).tar.gz"

mkdir -p $BACKUP_DIR

echo "Creating backup..."
tar -czf "$BACKUP_DIR/$BACKUP_NAME" -C $DATA_DIR config/ db/

echo "Backup created: $BACKUP_DIR/$BACKUP_NAME"

# Keep only last 7 backups
cd $BACKUP_DIR
ls -t *.tar.gz | tail -n +8 | xargs -r rm --
EOF
    
    # Status script
    cat > /usr/local/bin/netalertx-status << 'EOF'
#!/bin/bash
# NetAlertX Status Script

DATA_DIR="/opt/netalertx"

echo "=== NetAlertX Status ==="
echo
echo "Service Status:"
systemctl status netalertx.service --no-pager -l

echo
echo "Container Status:"
cd $DATA_DIR
docker compose ps

echo
echo "Container Logs (last 20 lines):"
docker logs netalertx --tail 20
EOF
    
    # Make scripts executable
    chmod +x /usr/local/bin/netalertx-*
    
    print_success "Management scripts created"
}

# Function to create initial configuration
create_initial_config() {
    print_status "Creating initial configuration..."
    
    # Create a basic app.conf if it doesn't exist
    if [ ! -f "$DATA_DIR/config/app.conf" ]; then
        cat > "$DATA_DIR/config/app.conf" << 'EOF'
# NetAlertX Configuration File
# This file is automatically generated and can be modified

# Network scanning settings
SCAN_SUBNETS = ["192.168.1.0/24"]
ARPSCAN_RUN_TIMEOUT = 30

# Web interface settings
REPORT_DASHBOARD_URL = "http://localhost:20211"

# Database settings
DB_PATH = "/app/db/app.db"

# Logging settings
LOG_LEVEL = "INFO"
LOG_PATH = "/app/log/"

# Plugin settings
LOADED_PLUGINS = ["ARPSCAN"]

# Notification settings (configure as needed)
NTFY_ENABLED = False
PUSHOVER_ENABLED = False
PUSHSAFER_ENABLED = False
EOF
    fi
    
    # Set ownership
    chown -R netalertx:netalertx $DATA_DIR
    
    print_success "Initial configuration created"
}

# Function to start NetAlertX
start_netalertx() {
    print_status "Starting NetAlertX..."
    
    cd $DATA_DIR
    
    # Pull the image first
    docker compose pull
    
    # Start the service
    systemctl start netalertx.service
    
    # Wait a moment for the container to start
    sleep 5
    
    # Check if container is running
    if docker compose ps | grep -q "Up"; then
        print_success "NetAlertX started successfully"
        
        # Get container IP
        CONTAINER_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+' | head -1)
        
        echo
        print_status "=== NetAlertX Installation Complete ==="
        echo "Access NetAlertX at: http://${CONTAINER_IP}:${NETALERTX_PORT}"
        echo "GraphQL API at: http://${CONTAINER_IP}:${GRAPHQL_PORT}"
        echo
        print_warning "Important:"
        echo "- Configure your network subnets in the web interface"
        echo "- Initial scan may take 5-10 minutes"
        echo "- Check logs with: netalertx-status"
        echo
    else
        print_error "Failed to start NetAlertX"
        docker compose logs
        exit 1
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -t, --type TYPE          Deployment type: development or production (default: development)"
    echo "  -p, --port PORT          NetAlertX web interface port (default: 20211)"
    echo "  -g, --graphql-port PORT  GraphQL API port (default: 20212)"
    echo "  -v, --version VERSION    NetAlertX version (default: latest)"
    echo "  --timezone TZ            Timezone (default: auto-detect)"
    echo "  -h, --help               Show this help message"
    echo
    echo "Examples:"
    echo "  $0                           # Basic development installation"
    echo "  $0 -t production            # Production installation"
    echo "  $0 -p 8080 -t development   # Development with custom port"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            DEPLOYMENT_TYPE="$2"
            shift 2
            ;;
        -p|--port)
            NETALERTX_PORT="$2"
            shift 2
            ;;
        -g|--graphql-port)
            GRAPHQL_PORT="$2"
            shift 2
            ;;
        -v|--version)
            NETALERTX_VERSION="$2"
            shift 2
            ;;
        --timezone)
            TIMEZONE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate deployment type
if [[ "$DEPLOYMENT_TYPE" != "development" && "$DEPLOYMENT_TYPE" != "production" ]]; then
    print_error "Invalid deployment type. Must be 'development' or 'production'"
    exit 1
fi

# Main installation function
main() {
    print_status "=== NetAlertX Installation Started ==="
    print_status "Deployment Type: $DEPLOYMENT_TYPE"
    print_status "Port: $NETALERTX_PORT"
    print_status "GraphQL Port: $GRAPHQL_PORT"
    print_status "Version: $NETALERTX_VERSION"
    echo
    
    check_root
    update_system
    install_docker
    setup_netalertx_user
    create_docker_compose
    setup_systemd_service
    
    if [ "$DEPLOYMENT_TYPE" = "production" ]; then
        configure_firewall
    fi
    
    create_management_scripts
    create_initial_config
    start_netalertx
    
    print_success "=== NetAlertX Installation Complete ==="
}

# Run main function
main "$@"
