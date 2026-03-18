#!/bin/bash

# NetAlertX Proxmox LXC Deployment Script
# This script creates and configures an LXC container on Proxmox for NetAlertX
# Based on the user's rules for supporting multiple Ubuntu versions and deployment targets

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration defaults
DEFAULT_VMID="200"
DEFAULT_HOSTNAME="netalertx"
DEFAULT_MEMORY="2048"
DEFAULT_CORES="2"
DEFAULT_DISK="20"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_UBUNTU_VERSION="24"
DEFAULT_DEPLOYMENT_TYPE="development"

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

# Function to check if running on Proxmox
check_proxmox() {
    if ! command -v pct &> /dev/null; then
        print_error "This script must be run on a Proxmox host (pct command not found)"
        exit 1
    fi
    
    if ! systemctl is-active --quiet pve-cluster; then
        print_error "Proxmox services are not running properly"
        exit 1
    fi
    
    print_success "Proxmox environment detected"
}

# Function to check if VMID is available
check_vmid_available() {
    local vmid=$1
    if pct list | grep -q "^${vmid}"; then
        return 1
    fi
    return 0
}

# Function to get next available VMID
get_next_vmid() {
    local start_vmid=$1
    local vmid=$start_vmid
    
    while ! check_vmid_available $vmid; do
        ((vmid++))
        if [ $vmid -gt 9999 ]; then
            print_error "No available VMID found"
            exit 1
        fi
    done
    
    echo $vmid
}

# Function to extract ubuntu templates from pveam available lines
extract_ubuntu_templates() {
    pveam available 2>/dev/null | grep -Eo 'ubuntu-[0-9]+\.[0-9]+-standard_[^[:space:]]+' | sort -u
}

# Function to select Ubuntu template
select_ubuntu_template() {
    local version=$1
    local major="$version"
    local template
    template=$(extract_ubuntu_templates | grep -E "ubuntu-${major}\.[0-9]+-standard_" | sort -u | head -n1)
    if [ -z "$template" ]; then
        print_error "No template matching Ubuntu major version ${major} found"
        exit 1
    fi
    echo "$template"
}

get_ubuntu_templates_by_major() {
    local major=$1
    extract_ubuntu_templates | grep -E "ubuntu-${major}\.[0-9]+-standard_" | sort -u
}

get_ubuntu_major_options() {
    extract_ubuntu_templates | sed -E 's/ubuntu-([0-9]+)\..*/\1/' | sort -u
}

# Function to check if template exists
check_template_exists() {
    local template=$1
    local storage=$2
    
    if ! pveam list $storage | grep -q "$template"; then
        print_warning "Template $template not found in storage $storage"
        print_status "Downloading template..."
        pveam download $storage $template
        if [ $? -eq 0 ]; then
            print_success "Template downloaded successfully"
        else
            print_error "Failed to download template"
            exit 1
        fi
    else
        print_success "Template $template found in storage"
    fi
}

# Interactive configuration function
interactive_config() {
    echo
    print_status "=== NetAlertX LXC Container Configuration ==="
    echo
    
    # VMID
    while true; do
        read -p "Enter VMID [$DEFAULT_VMID]: " VMID
        VMID=${VMID:-$DEFAULT_VMID}
        
        if ! [[ "$VMID" =~ ^[0-9]+$ ]] || [ "$VMID" -lt 100 ] || [ "$VMID" -gt 9999 ]; then
            print_error "VMID must be a number between 100 and 9999"
            continue
        fi
        
        if ! check_vmid_available $VMID; then
            print_warning "VMID $VMID is already in use"
            VMID=$(get_next_vmid $VMID)
            print_status "Using next available VMID: $VMID"
        fi
        break
    done
    
    # Hostname
    read -p "Enter hostname [$DEFAULT_HOSTNAME]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$DEFAULT_HOSTNAME}
    
    # Ubuntu version (choose from available ubuntu templates)
    echo
    print_status "Fetching available Ubuntu templates from pveam..."
    local ubuntu_majors
    ubuntu_majors=$(get_ubuntu_major_options)
    if [ -z "$ubuntu_majors" ]; then
        print_error "No Ubuntu templates available from pveam available"
        exit 1
    fi

    echo "Available Ubuntu major versions:" 
    local default_major=""
    while IFS= read -r maj; do
        if [ -z "$default_major" ]; then
            default_major="$maj"
        fi
        echo "  $maj) Ubuntu $maj.04 (from available templates)"
    done <<< "$ubuntu_majors"

    if [ -z "$default_major" ]; then
        print_error "No Ubuntu major versions found"
        exit 1
    fi

    read -p "Select Ubuntu major version [$default_major]: " major_choice
    major_choice=${major_choice:-$default_major}
    if ! echo "$ubuntu_majors" | grep -xq "$major_choice"; then
        print_error "Invalid choice: $major_choice"
        exit 1
    fi
    UBUNTU_VERSION=$major_choice

    print_status "Selected Ubuntu major version: $UBUNTU_VERSION"

    # Deployment type
    echo
    print_status "Deployment types:"
    echo "  development - Basic setup with minimal resources"
    echo "  production  - Enhanced setup with more resources and security"
    read -p "Select deployment type [$DEFAULT_DEPLOYMENT_TYPE]: " DEPLOYMENT_TYPE
    DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-$DEFAULT_DEPLOYMENT_TYPE}
    
    # Adjust resources based on deployment type
    if [ "$DEPLOYMENT_TYPE" = "production" ]; then
        DEFAULT_MEMORY="4096"
        DEFAULT_CORES="4"
        DEFAULT_DISK="40"
    fi
    
    # Memory
    read -p "Enter memory in MB [$DEFAULT_MEMORY]: " MEMORY
    MEMORY=${MEMORY:-$DEFAULT_MEMORY}
    
    # CPU cores
    read -p "Enter CPU cores [$DEFAULT_CORES]: " CORES
    CORES=${CORES:-$DEFAULT_CORES}
    
    # Disk size
    read -p "Enter disk size in GB [$DEFAULT_DISK]: " DISK
    DISK=${DISK:-$DEFAULT_DISK}
    
    # Network bridge
    read -p "Enter network bridge [$DEFAULT_BRIDGE]: " BRIDGE
    BRIDGE=${BRIDGE:-$DEFAULT_BRIDGE}
    
    # Storage location
    STORAGE_INFO=$(pvesm status -content rootdir 2>/dev/null | tail -n +2)
    STORAGE=$(echo "$STORAGE_INFO" | awk '{print $1}' | head -1)
    STORAGE=${STORAGE:-local-lvm}
    
    echo
    print_status "=== Configuration Summary ==="
    echo "VMID: $VMID"
    echo "Hostname: $HOSTNAME"
    echo "Ubuntu Version: $UBUNTU_VERSION"
    echo "Deployment Type: $DEPLOYMENT_TYPE"
    echo "Memory: ${MEMORY}MB"
    echo "CPU Cores: $CORES"
    echo "Disk: ${DISK}GB"
    echo "Network Bridge: $BRIDGE"
    echo "Storage: $STORAGE"
    echo
    
    read -p "Continue with these settings? [y/N]: " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
}

# Function to create LXC container
create_container() {
    print_status "Creating LXC container..."
    
    local template=$(select_ubuntu_template $UBUNTU_VERSION)
    check_template_exists $template $STORAGE
    
    # Create the container
    pct create $VMID $STORAGE:vztmpl/$template \
        --hostname $HOSTNAME \
        --memory $MEMORY \
        --cores $CORES \
        --rootfs $STORAGE:$DISK \
        --net0 name=eth0,bridge=$BRIDGE,firewall=1,ip=dhcp \
        --ostype ubuntu \
        --unprivileged 1 \
        --features nesting=1,keyctl=1 \
        --startup order=3 \
        --onboot 1
    
    if [ $? -eq 0 ]; then
        print_success "LXC container $VMID created successfully"
    else
        print_error "Failed to create LXC container"
        exit 1
    fi
}

# Function to start container and wait for it to be ready
start_and_wait() {
    print_status "Starting container..."
    pct start $VMID
    
    print_status "Waiting for container to be ready..."
    sleep 10
    
    # Wait for container to have network connectivity
    for i in {1..30}; do
        if pct exec $VMID -- ping -c 1 8.8.8.8 &>/dev/null; then
            print_success "Container is ready"
            return 0
        fi
        sleep 2
    done
    
    print_error "Container failed to start properly"
    exit 1
}

# Function to install Docker in the container
install_docker() {
    print_status "Installing Docker in container..."
    
    # Update system
    pct exec $VMID -- bash -c "apt-get update && apt-get upgrade -y"
    
    # Install prerequisites
    pct exec $VMID -- bash -c "apt-get install -y ca-certificates curl gnupg lsb-release"
    
    # Add Docker's official GPG key
    pct exec $VMID -- bash -c "install -m 0755 -d /etc/apt/keyrings"
    pct exec $VMID -- bash -c "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    
    # Add Docker repository
    pct exec $VMID -- bash -c "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null"
    
    # Install Docker
    pct exec $VMID -- bash -c "apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    
    # Enable and start Docker
    pct exec $VMID -- systemctl enable docker
    pct exec $VMID -- systemctl start docker
    
    # Verify Docker installation
    if pct exec $VMID -- docker --version; then
        print_success "Docker installed successfully"
    else
        print_error "Docker installation failed"
        exit 1
    fi
}

# Function to deploy NetAlertX
deploy_netalertx() {
    print_status "Deploying NetAlertX..."
    
    # Create directories
    pct exec $VMID -- mkdir -p /opt/netalertx/{config,db,logs}
    
    # Create docker-compose.yml
    cat > /tmp/netalertx-compose.yml << 'EOF'
version: '3.8'
services:
  netalertx:
    image: ghcr.io/jokob-sk/netalertx:latest
    container_name: netalertx
    network_mode: host
    restart: unless-stopped
    volumes:
      - /opt/netalertx/config:/app/config
      - /opt/netalertx/db:/app/db
      - /opt/netalertx/logs:/app/log
    tmpfs:
      - /app/api:size=100M
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
      - PORT=20211
      - LISTEN_ADDR=0.0.0.0
    cap_add:
      - NET_ADMIN
      - NET_RAW
EOF
    
    # Copy compose file to container
    pct push $VMID /tmp/netalertx-compose.yml /opt/netalertx/docker-compose.yml
    
    # Set ownership
    pct exec $VMID -- chown -R 1000:1000 /opt/netalertx
    
    # Start NetAlertX
    pct exec $VMID -- bash -c "cd /opt/netalertx && docker compose up -d"
    
    # Clean up temp file
    rm /tmp/netalertx-compose.yml
    
    if [ $? -eq 0 ]; then
        print_success "NetAlertX deployed successfully"
    else
        print_error "NetAlertX deployment failed"
        exit 1
    fi
}

# Function to get container IP
get_container_ip() {
    local ip=$(pct exec $VMID -- ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+' | head -1)
    echo $ip
}

# Function to setup production enhancements
setup_production() {
    if [ "$DEPLOYMENT_TYPE" != "production" ]; then
        return 0
    fi
    
    print_status "Setting up production enhancements..."
    
    # Install fail2ban
    pct exec $VMID -- apt-get install -y fail2ban
    
    # Setup automatic updates
    pct exec $VMID -- apt-get install -y unattended-upgrades
    
    # Configure firewall
    pct exec $VMID -- ufw --force enable
    pct exec $VMID -- ufw allow 20211/tcp
    pct exec $VMID -- ufw allow ssh
    
    print_success "Production enhancements configured"
}

# Function to create update script
create_update_script() {
    cat > /tmp/update-netalertx.sh << 'EOF'
#!/bin/bash
# NetAlertX Update Script
echo "Updating NetAlertX..."
cd /opt/netalertx
docker compose pull
docker compose up -d
docker image prune -f
echo "Update completed"
EOF
    
    pct push $VMID /tmp/update-netalertx.sh /usr/local/bin/update-netalertx.sh
    pct exec $VMID -- chmod +x /usr/local/bin/update-netalertx.sh
    rm /tmp/update-netalertx.sh
}

# Main function
main() {
    print_status "=== NetAlertX Proxmox LXC Deployment ==="
    echo
    
    # Check if running on Proxmox
    check_proxmox
    
    # Interactive configuration
    interactive_config
    
    # Create and configure container
    create_container
    start_and_wait
    install_docker
    deploy_netalertx
    setup_production
    create_update_script
    
    # Get container IP for final message
    CONTAINER_IP=$(get_container_ip)
    
    echo
    print_success "=== Deployment Complete ==="
    echo
    print_status "Container Details:"
    echo "  VMID: $VMID"
    echo "  Hostname: $HOSTNAME"
    echo "  IP Address: $CONTAINER_IP"
    echo "  NetAlertX URL: http://$CONTAINER_IP:20211"
    echo
    print_status "Management Commands:"
    echo "  Start container: pct start $VMID"
    echo "  Stop container: pct stop $VMID"
    echo "  Update NetAlertX: pct exec $VMID -- /usr/local/bin/update-netalertx.sh"
    echo "  View logs: pct exec $VMID -- docker logs netalertx"
    echo
    print_warning "Important Notes:"
    echo "  - Initial scan may take 5-10 minutes"
    echo "  - Configure your network subnets in the NetAlertX settings"
    echo "  - Check the logs if NetAlertX doesn't detect devices"
    echo
}

# Run main function
main "$@"