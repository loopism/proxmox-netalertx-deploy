# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This repository contains automation scripts for deploying NetAlertX (network monitoring and alerting system) in LXC containers on Proxmox Virtual Environment. It provides fully automated but interactive installation supporting multiple Ubuntu versions (22.04 LTS and 24.04 LTS) and deployment targets (development and production).

## Architecture

The deployment system follows a multi-layered approach:

1. **Host Layer (Proxmox)**: Main deployment script (`deploy-netalertx.sh`) runs on Proxmox host
2. **Container Layer (LXC)**: Installation script (`install-netalertx.sh`) executes inside the container
3. **Application Layer (Docker)**: NetAlertX runs as a Docker container within the LXC container
4. **Configuration Layer**: Templates and environment files provide customizable settings

**Data Flow**: User interaction → Proxmox deployment script → LXC container creation → Docker setup → NetAlertX service startup → Web interface availability

## Commonly Used Commands

### Initial Deployment
```bash path=null start=null
# Make scripts executable (required after cloning)
chmod +x *.sh scripts/*.sh

# Start interactive deployment
./deploy-netalertx.sh

# Deploy with specific parameters (bypassing some prompts)
./deploy-netalertx.sh --vmid 250 --hostname netalertx-prod --type production
```

### Container Management
```bash path=null start=null
# Container operations (run on Proxmox host)
pct start [VMID]                    # Start container
pct stop [VMID]                     # Stop container  
pct restart [VMID]                  # Restart container
pct status [VMID]                   # Check container status
pct exec [VMID] -- [command]        # Execute command in container

# NetAlertX management (inside container)
pct exec [VMID] -- netalertx-update   # Update to latest version
pct exec [VMID] -- netalertx-backup   # Create backup
pct exec [VMID] -- netalertx-status   # Show status and logs
```

### Maintenance and Cleanup
```bash path=null start=null
# Show all cleanup options
./scripts/cleanup.sh help

# Common maintenance tasks
./scripts/cleanup.sh status [VMID]        # Check status
./scripts/cleanup.sh maintenance [VMID]   # Perform maintenance
./scripts/cleanup.sh update [VMID]        # Update NetAlertX
./scripts/cleanup.sh reset [VMID]         # Reset NetAlertX data
./scripts/cleanup.sh cleanup [VMID]       # Complete removal

# Docker operations within container
pct exec [VMID] -- docker logs netalertx               # View logs
pct exec [VMID] -- docker compose ps                   # Container status
pct exec [VMID] -- docker compose -f /opt/netalertx/docker-compose.yml restart
```

### Development and Testing
```bash path=null start=null
# Test deployment without permanent changes
pct create 999 local:vztmpl/ubuntu-24.04-standard_24.04-1_amd64.tar.zst --hostname test-netalertx

# Quick NetAlertX restart for testing config changes
pct exec [VMID] -- systemctl restart netalertx.service

# View real-time logs
pct exec [VMID] -- docker logs netalertx --follow
```

## Configuration Files Structure

### Core Configuration Files

- **`config/netalertx.env`**: Environment variables template with network settings, plugin configuration, and notification options
- **`config/app.conf.template`**: NetAlertX application configuration covering scanning, alerting, and integrations
- **`lxc-config-template.conf`**: LXC container resource templates for different deployment scenarios

### Key Configuration Sections

**Network Configuration** (netalertx.env):
```bash path=null start=null
SCAN_SUBNETS=["192.168.1.0/24"]     # Target network(s) to scan
PORT=20211                          # Web interface port
GRAPHQL_PORT=20212                  # API port
LOADED_PLUGINS=["ARPSCAN","PIHOLE"] # Active plugins
```

**LXC Resource Templates** (lxc-config-template.conf):
- `development`: 2GB RAM, 2 CPU, 20GB disk
- `production`: 4GB RAM, 4 CPU, 40GB disk  
- `minimal`: 1GB RAM, 1 CPU, 10GB disk (testing)
- `high-performance`: 8GB RAM, 8 CPU, 80GB disk (large networks)

## Deployment Workflows

### Fresh Installation
1. Clone repository to Proxmox host
2. Run `chmod +x *.sh scripts/*.sh`
3. Execute `./deploy-netalertx.sh`
4. Follow interactive prompts for VMID, hostname, Ubuntu version, deployment type
5. Wait for automatic container creation, Docker setup, and NetAlertX startup
6. Access web interface at provided URL

### Production Deployment
- Uses enhanced security (UFW firewall, fail2ban)
- Includes automatic backups and maintenance
- More resources allocated by default
- Health checks and monitoring enabled

### Update Procedure
1. Use built-in update: `./scripts/cleanup.sh update [VMID]`
2. Or manual update inside container: `pct exec [VMID] -- netalertx-update`
3. Updates pull latest Docker image and restart services
4. Automatic backup created before update

## Integration Points

### Plugin Integrations
- **Pi-hole**: Enhanced device discovery via DNS logs
- **UniFi**: Network equipment integration for enterprise environments  
- **DHCP Leases**: Device name resolution from DHCP server
- **MQTT/Home Assistant**: Smart home integration

### External Dependencies
- Proxmox VE 7.0+ with `pct` command availability
- Internet connectivity for downloading Ubuntu templates and Docker images
- Network bridge configuration (typically `vmbr0`)

## Development Notes

### Testing Different Configurations
- Use `minimal` configuration template for quick testing
- Development mode skips firewall setup for easier debugging
- Container logs available at `/var/log/pve/lxc/[VMID].log` on Proxmox host

### Customization Points
- Modify `lxc-config-template.conf` for custom resource allocations
- Update `config/netalertx.env` template for different default settings
- Extend `scripts/cleanup.sh` for additional maintenance tasks

### Common Development Tasks
- Test script changes: Use high VMID numbers (900+) for temporary containers
- Verify template downloads: Check `pveam list local` for available Ubuntu templates
- Debug container issues: Use `pct enter [VMID]` for direct container access
- Monitor resource usage: `pct exec [VMID] -- htop` or `pct exec [VMID] -- df -h`

## File Structure

```
proxmox-netalertx-deploy/
├── deploy-netalertx.sh           # Main Proxmox deployment script
├── install-netalertx.sh          # Container installation script
├── lxc-config-template.conf      # LXC resource templates
├── setup.bat                     # Windows setup helper
├── config/
│   ├── netalertx.env            # Environment variables template
│   └── app.conf.template        # NetAlertX config template
└── scripts/
    └── cleanup.sh               # Maintenance utilities
```

## Troubleshooting Commands

```bash path=null start=null
# Container won't start
pct config [VMID]                     # Check container configuration
pct start [VMID]                      # Attempt start with verbose output

# NetAlertX not detecting devices  
pct exec [VMID] -- docker logs netalertx --tail 50
pct exec [VMID] -- ping 8.8.8.8       # Test network connectivity
pct exec [VMID] -- arp-scan -l         # Test ARP scanning

# Web interface inaccessible
pct exec [VMID] -- netstat -tlnp | grep 20211
pct exec [VMID] -- ufw status          # Check firewall (production mode)
pct exec [VMID] -- ip addr show eth0   # Get container IP

# Performance issues
./scripts/cleanup.sh status [VMID]     # Resource usage overview
pct exec [VMID] -- docker stats netalertx --no-stream
```
