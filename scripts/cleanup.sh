#!/bin/bash

# NetAlertX Cleanup and Maintenance Scripts
# This script provides various cleanup and maintenance functions

set -e

# Color codes for output
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

# Function to stop and remove NetAlertX container
cleanup_container() {
    local vmid=$1
    
    if [ -z "$vmid" ]; then
        print_error "VMID is required for container cleanup"
        return 1
    fi
    
    print_status "Stopping and removing NetAlertX container (VMID: $vmid)..."
    
    # Stop the container
    if pct status $vmid | grep -q "running"; then
        print_status "Stopping container $vmid..."
        pct stop $vmid
        sleep 5
    fi
    
    # Create backup before removal
    create_final_backup $vmid
    
    # Remove the container
    print_warning "About to remove container $vmid permanently!"
    read -p "Are you sure? This action cannot be undone! [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        pct destroy $vmid
        print_success "Container $vmid removed successfully"
    else
        print_status "Container removal cancelled"
    fi
}

# Function to create a final backup before cleanup
create_final_backup() {
    local vmid=$1
    local backup_dir="/var/lib/vz/dump"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    print_status "Creating final backup before cleanup..."
    
    # Create backup directory if it doesn't exist
    mkdir -p $backup_dir
    
    # Create container backup
    if pct status $vmid &>/dev/null; then
        vzdump $vmid --compress lzo --storage local --tmpdir /tmp
        print_success "Container backup created in $backup_dir"
    fi
    
    # Backup NetAlertX data if container is running
    if pct status $vmid | grep -q "running"; then
        local data_backup="/tmp/netalertx-data-backup-${timestamp}.tar.gz"
        pct exec $vmid -- tar -czf - /opt/netalertx > $data_backup
        print_success "NetAlertX data backup created: $data_backup"
    fi
}

# Function to clean up Docker resources
cleanup_docker() {
    local vmid=$1
    
    if [ -z "$vmid" ]; then
        print_error "VMID is required for Docker cleanup"
        return 1
    fi
    
    print_status "Cleaning up Docker resources in container $vmid..."
    
    if pct status $vmid | grep -q "running"; then
        # Stop NetAlertX containers
        pct exec $vmid -- docker compose -f /opt/netalertx/docker-compose.yml down || true
        
        # Remove NetAlertX images
        pct exec $vmid -- docker rmi ghcr.io/jokob-sk/netalertx:latest || true
        
        # Clean up unused Docker resources
        pct exec $vmid -- docker system prune -af
        
        # Remove Docker volumes (careful with this)
        read -p "Remove Docker volumes? This will delete all Docker data! [y/N]: " confirm_volumes
        if [[ "$confirm_volumes" =~ ^[Yy]$ ]]; then
            pct exec $vmid -- docker volume prune -f
        fi
        
        print_success "Docker cleanup completed"
    else
        print_warning "Container $vmid is not running, skipping Docker cleanup"
    fi
}

# Function to clean up host resources
cleanup_host() {
    print_status "Cleaning up Proxmox host resources..."
    
    # Clean up downloaded templates (optional)
    read -p "Clean up downloaded Ubuntu templates? [y/N]: " confirm_templates
    if [[ "$confirm_templates" =~ ^[Yy]$ ]]; then
        # List and optionally remove templates
        print_status "Available templates:"
        pveam list local | grep ubuntu
        
        read -p "Enter template name to remove (or 'skip' to skip): " template_name
        if [[ "$template_name" != "skip" && -n "$template_name" ]]; then
            pveam remove local:vztmpl/$template_name
            print_success "Template $template_name removed"
        fi
    fi
    
    # Clean up old backups
    read -p "Clean up old backups older than 30 days? [y/N]: " confirm_backups
    if [[ "$confirm_backups" =~ ^[Yy]$ ]]; then
        find /var/lib/vz/dump -name "*.tar.*" -mtime +30 -delete
        print_success "Old backups cleaned up"
    fi
    
    print_success "Host cleanup completed"
}

# Function to reset NetAlertX data (keep container, reset app)
reset_netalertx() {
    local vmid=$1
    
    if [ -z "$vmid" ]; then
        print_error "VMID is required for NetAlertX reset"
        return 1
    fi
    
    print_warning "This will reset all NetAlertX data (database, config, logs)"
    read -p "Are you sure you want to continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_status "Reset cancelled"
        return 0
    fi
    
    print_status "Resetting NetAlertX data in container $vmid..."
    
    if pct status $vmid | grep -q "running"; then
        # Stop NetAlertX
        pct exec $vmid -- systemctl stop netalertx.service || true
        pct exec $vmid -- docker compose -f /opt/netalertx/docker-compose.yml down || true
        
        # Create backup before reset
        local timestamp=$(date +%Y%m%d_%H%M%S)
        pct exec $vmid -- tar -czf /tmp/netalertx-backup-before-reset-${timestamp}.tar.gz /opt/netalertx/
        
        # Remove data directories
        pct exec $vmid -- rm -rf /opt/netalertx/config/*
        pct exec $vmid -- rm -rf /opt/netalertx/db/*
        pct exec $vmid -- rm -rf /opt/netalertx/logs/*
        
        # Recreate directories with proper permissions
        pct exec $vmid -- mkdir -p /opt/netalertx/{config,db,logs,backups}
        pct exec $vmid -- chown -R netalertx:netalertx /opt/netalertx
        
        # Restart NetAlertX
        pct exec $vmid -- systemctl start netalertx.service
        
        print_success "NetAlertX data reset completed"
        print_status "Backup created at: /tmp/netalertx-backup-before-reset-${timestamp}.tar.gz"
    else
        print_warning "Container $vmid is not running, cannot reset NetAlertX"
    fi
}

# Function to update NetAlertX to latest version
update_netalertx() {
    local vmid=$1
    
    if [ -z "$vmid" ]; then
        print_error "VMID is required for NetAlertX update"
        return 1
    fi
    
    print_status "Updating NetAlertX in container $vmid..."
    
    if pct status $vmid | grep -q "running"; then
        # Run the update script inside the container
        pct exec $vmid -- /usr/local/bin/netalertx-update
        print_success "NetAlertX update completed"
    else
        print_warning "Container $vmid is not running, cannot update NetAlertX"
    fi
}

# Function to display container status and resource usage
show_status() {
    local vmid=$1
    
    if [ -z "$vmid" ]; then
        print_error "VMID is required for status display"
        return 1
    fi
    
    print_status "=== Container $vmid Status ==="
    echo
    
    # Container status
    echo "Container Status:"
    pct status $vmid
    echo
    
    # Resource usage
    if pct status $vmid | grep -q "running"; then
        echo "Resource Usage:"
        pct exec $vmid -- df -h
        echo
        pct exec $vmid -- free -h
        echo
        
        # NetAlertX specific status
        echo "NetAlertX Status:"
        pct exec $vmid -- systemctl status netalertx.service --no-pager || true
        echo
        
        echo "Docker Status:"
        pct exec $vmid -- docker compose -f /opt/netalertx/docker-compose.yml ps || true
        echo
        
        echo "Recent Logs:"
        pct exec $vmid -- docker logs netalertx --tail 10 || true
    else
        print_warning "Container is not running"
    fi
}

# Function to perform maintenance tasks
perform_maintenance() {
    local vmid=$1
    
    if [ -z "$vmid" ]; then
        print_error "VMID is required for maintenance"
        return 1
    fi
    
    print_status "Performing maintenance on container $vmid..."
    
    if pct status $vmid | grep -q "running"; then
        # Update system packages
        pct exec $vmid -- apt-get update
        pct exec $vmid -- apt-get upgrade -y
        
        # Clean up package cache
        pct exec $vmid -- apt-get autoremove -y
        pct exec $vmid -- apt-get autoclean
        
        # Docker maintenance
        pct exec $vmid -- docker system prune -f
        
        # NetAlertX log rotation
        pct exec $vmid -- find /opt/netalertx/logs -name "*.log" -mtime +30 -delete
        
        # Create maintenance backup
        pct exec $vmid -- /usr/local/bin/netalertx-backup
        
        print_success "Maintenance completed"
    else
        print_warning "Container $vmid is not running, cannot perform maintenance"
    fi
}

# Function to display usage
usage() {
    echo "Usage: $0 COMMAND [VMID]"
    echo
    echo "Commands:"
    echo "  cleanup VMID         - Complete cleanup (remove container and data)"
    echo "  cleanup-docker VMID  - Clean up Docker resources only"
    echo "  cleanup-host         - Clean up Proxmox host resources"
    echo "  reset VMID           - Reset NetAlertX data (keep container)"
    echo "  update VMID          - Update NetAlertX to latest version"
    echo "  status VMID          - Show container and NetAlertX status"
    echo "  maintenance VMID     - Perform maintenance tasks"
    echo "  help                 - Show this help message"
    echo
    echo "Examples:"
    echo "  $0 cleanup 200       # Complete cleanup of container 200"
    echo "  $0 reset 200         # Reset NetAlertX in container 200"
    echo "  $0 status 200        # Show status of container 200"
}

# Main function
main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi
    
    local command=$1
    local vmid=$2
    
    case $command in
        "cleanup")
            cleanup_container $vmid
            ;;
        "cleanup-docker")
            cleanup_docker $vmid
            ;;
        "cleanup-host")
            cleanup_host
            ;;
        "reset")
            reset_netalertx $vmid
            ;;
        "update")
            update_netalertx $vmid
            ;;
        "status")
            show_status $vmid
            ;;
        "maintenance")
            perform_maintenance $vmid
            ;;
        "help"|"-h"|"--help")
            usage
            exit 0
            ;;
        *)
            print_error "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

# Check if running on Proxmox
if ! command -v pct &> /dev/null; then
    print_error "This script must be run on a Proxmox host"
    exit 1
fi

# Run main function
main "$@"
