# NetAlertX Proxmox LXC Deployment

A comprehensive automation script for deploying [NetAlertX](https://github.com/jokob-sk/NetAlertX) network monitoring and alerting system in an LXC container on Proxmox Virtual Environment.

## 🚀 Features

- **Fully Automated Deployment**: One-script installation of NetAlertX in LXC container
- **Interactive Configuration**: Guided setup with sensible defaults
- **Multi-Ubuntu Support**: Ubuntu 22.04 LTS and 24.04 LTS support
- **Dual Deployment Modes**: Development and Production configurations
- **Built-in Management Tools**: Update, backup, maintenance, and cleanup scripts
- **Security Hardening**: Production mode includes firewall and security configurations
- **Comprehensive Documentation**: Step-by-step guides and troubleshooting

## 📋 Table of Contents

- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [Installation Guide](#-installation-guide)
- [Configuration](#-configuration)
- [Management](#-management)
- [Troubleshooting](#-troubleshooting)
- [Advanced Usage](#-advanced-usage)
- [Security](#-security)
- [Contributing](#-contributing)

## 🔧 Prerequisites

### Proxmox Host Requirements
- Proxmox VE 7.0 or later
- Root access to Proxmox host
- Minimum 2GB available RAM
- 20GB+ available storage
- Internet connectivity for downloading templates and Docker images

### Network Requirements
- Network bridge configured (typically `vmbr0`)
- DHCP server on target network (or static IP configuration)
- Outbound internet access for container

### Optional Requirements
- Pi-hole instance (for enhanced device discovery)
- DHCP server with accessible lease files
- UniFi controller (for UniFi network integration)

## 🚀 Quick Start

1. **Download and setup the deployment scripts:**
   ```bash
   git clone <repository-url>
   cd proxmox-netalertx-deploy
   chmod +x *.sh scripts/*.sh
   ```

2. **Run the deployment script:**
   ```bash
   ./deploy-netalertx.sh
   ```

3. **Follow the interactive prompts** to configure your deployment

4. **Access NetAlertX** at the provided URL once deployment completes

## 📖 Installation Guide

### Step 1: Prepare Proxmox Host

Ensure your Proxmox host is ready:

```bash
# Update Proxmox (optional but recommended)
apt update && apt upgrade -y

# Verify pct command is available
pct --version

# Check available storage
pvesm status
```

### Step 2: Download Deployment Scripts

```bash
# Clone the repository
git clone <repository-url>
cd proxmox-netalertx-deploy

# Make scripts executable
chmod +x deploy-netalertx.sh install-netalertx.sh scripts/cleanup.sh
```

### Step 3: Run Deployment

Execute the main deployment script:

```bash
./deploy-netalertx.sh
```

The script will guide you through configuration options:

- **VMID**: Container ID (default: 200)
- **Hostname**: Container hostname (default: netalertx)  
- **Ubuntu Version**: 22 or 24 (default: 24)
- **Deployment Type**: development or production (default: development)
- **Resources**: Memory, CPU, disk allocation
- **Network**: Bridge selection

### Step 4: Initial Configuration

Once deployed, access the NetAlertX web interface:

1. Note the IP address provided at the end of deployment
2. Open `http://[CONTAINER_IP]:20211` in your web browser
3. Configure your network subnets in the NetAlertX settings
4. Wait 5-10 minutes for the initial network scan to complete

## ⚙️ Configuration

### Deployment Types

#### Development Mode
- **Resources**: 2GB RAM, 2 CPU cores, 20GB disk
- **Security**: Basic configuration, no firewall
- **Features**: Standard logging, basic monitoring
- **Use Case**: Testing, small networks, development

#### Production Mode  
- **Resources**: 4GB RAM, 4 CPU cores, 40GB disk
- **Security**: UFW firewall, fail2ban, automatic updates
- **Features**: Enhanced logging, health checks, backups
- **Use Case**: Production environments, larger networks

### Network Configuration

Edit network settings in the NetAlertX web interface or configuration files:

```bash
# Access container to modify config
pct exec [VMID] -- nano /opt/netalertx/config/app.conf
```

Key network settings:
```python
SCAN_SUBNETS = ['192.168.1.0/24']  # Your network subnet(s)
SCAN_CYCLE_MINUTES = 5             # Scan frequency
ARPSCAN_RUN_TIMEOUT = 30           # ARP scan timeout
```

### Environment Variables

Configuration can be managed via environment files:

```bash
# Copy and customize environment template
cp config/netalertx.env.template /path/to/your/netalertx.env

# Key variables to customize:
# TZ=America/New_York              # Your timezone
# SCAN_SUBNETS=["192.168.1.0/24"]  # Your network
# LOADED_PLUGINS=["ARPSCAN","PIHOLE"]  # Enabled plugins
```

## 🔧 Management

### Built-in Management Commands

After deployment, several management commands are available:

```bash
# Container management (run on Proxmox host)
pct start [VMID]     # Start container
pct stop [VMID]      # Stop container  
pct restart [VMID]   # Restart container

# NetAlertX management (run inside container)
pct exec [VMID] -- netalertx-update   # Update to latest version
pct exec [VMID] -- netalertx-backup   # Create backup
pct exec [VMID] -- netalertx-status   # Show status and logs
```

### Cleanup and Maintenance

Use the provided cleanup script for various maintenance tasks:

```bash
# Show all available commands
./scripts/cleanup.sh help

# Check status
./scripts/cleanup.sh status [VMID]

# Perform maintenance
./scripts/cleanup.sh maintenance [VMID]

# Update NetAlertX
./scripts/cleanup.sh update [VMID]

# Reset NetAlertX data (keeps container)
./scripts/cleanup.sh reset [VMID]

# Complete cleanup (removes container)
./scripts/cleanup.sh cleanup [VMID]
```

### Backups

Automated backups are configured by default:

- **Container Backups**: Proxmox VZ dump format
- **Data Backups**: NetAlertX configuration and database
- **Schedule**: Daily at 1 AM (configurable)
- **Retention**: 7 days for data backups, 30 days for container backups

Manual backup:
```bash
# Create immediate backup
pct exec [VMID] -- /usr/local/bin/netalertx-backup

# Container snapshot
pct snapshot [VMID] manual-snapshot
```

## 🔍 Troubleshooting

### Common Issues

#### NetAlertX Not Detecting Devices

1. **Check network configuration:**
   ```bash
   pct exec [VMID] -- docker logs netalertx
   ```

2. **Verify subnet configuration:**
   - Access web interface → Settings
   - Ensure `SCAN_SUBNETS` matches your network
   - Example: `192.168.1.0/24` for typical home networks

3. **Check container network access:**
   ```bash
   pct exec [VMID] -- ping 8.8.8.8
   pct exec [VMID] -- arp-scan -l
   ```

#### Container Won't Start

1. **Check container status:**
   ```bash
   pct status [VMID]
   pct config [VMID]
   ```

2. **Review container logs:**
   ```bash
   pct start [VMID]
   # Check /var/log/pve/lxc/[VMID].log on Proxmox host
   ```

3. **Verify resources:**
   ```bash
   pvesm status  # Check storage availability
   free -h       # Check host memory
   ```

#### Docker Issues

1. **Check Docker status:**
   ```bash
   pct exec [VMID] -- systemctl status docker
   pct exec [VMID] -- docker version
   ```

2. **Restart Docker service:**
   ```bash
   pct exec [VMID] -- systemctl restart docker
   pct exec [VMID] -- systemctl start netalertx.service
   ```

#### Web Interface Not Accessible

1. **Check if NetAlertX is running:**
   ```bash
   pct exec [VMID] -- docker ps
   pct exec [VMID] -- netstat -tlnp | grep 20211
   ```

2. **Verify firewall settings:**
   ```bash
   # On container (if using production mode)
   pct exec [VMID] -- ufw status

   # On Proxmox host
   iptables -L -n
   ```

3. **Check container IP:**
   ```bash
   pct exec [VMID] -- ip addr show eth0
   ```

### Log Locations

- **Container logs**: `/var/log/pve/lxc/[VMID].log` (on Proxmox host)
- **NetAlertX logs**: `/opt/netalertx/logs/` (inside container)
- **Docker logs**: `docker logs netalertx` (inside container)
- **System logs**: `journalctl -u netalertx.service` (inside container)

### Performance Tuning

#### For Large Networks (500+ devices)

1. **Increase resources:**
   ```bash
   pct set [VMID] --memory 6144 --cores 6
   ```

2. **Optimize scan settings:**
   ```python
   # In app.conf
   MAX_CONCURRENT_SCANS = 5
   SCAN_TIMEOUT = 120
   CACHE_TTL = 600
   ```

#### For Small Networks (<50 devices)

1. **Reduce resources:**
   ```bash
   pct set [VMID] --memory 1024 --cores 1
   ```

2. **Increase scan frequency:**
   ```python
   # In app.conf
   SCAN_CYCLE_MINUTES = 2
   ```

## 🔐 Security

### Production Security Features

Production deployments include several security enhancements:

- **UFW Firewall**: Blocks unnecessary ports
- **Fail2ban**: Intrusion prevention
- **Automatic Updates**: Security patches
- **Non-root User**: NetAlertX runs as dedicated user
- **Container Hardening**: Security options enabled

### Additional Security Recommendations

1. **Network Isolation:**
   ```bash
   # Create dedicated VLAN for monitoring
   # Use firewall rules to restrict container access
   ```

2. **Access Control:**
   ```bash
   # Enable authentication in NetAlertX (if supported)
   # Use reverse proxy with authentication
   ```

3. **Certificate Management:**
   ```bash
   # Consider SSL/TLS termination at reverse proxy
   # Regular certificate rotation
   ```

## 📊 Advanced Usage

### Pi-hole Integration

If you have Pi-hole running, enable enhanced device discovery:

1. **Configure Pi-hole plugin:**
   ```python
   # In app.conf or via environment
   LOADED_PLUGINS = ["ARPSCAN", "PIHOLE"]
   PIHOLE_DB_PATH = "/path/to/pihole-FTL.db"
   ```

2. **Mount Pi-hole database:**
   ```bash
   # Add bind mount to container
   pct set [VMID] --mp1 /opt/pihole/etc/pihole,mp=/mnt/pihole,ro=1
   ```

### UniFi Integration

For UniFi networks:

1. **Enable UniFi plugin:**
   ```python
   LOADED_PLUGINS = ["ARPSCAN", "UNIFI"]
   UNIFI_URL = "https://your-controller:8443"
   UNIFI_USERNAME = "readonly-user"
   UNIFI_PASSWORD = "password"
   ```

### Home Assistant Integration

Connect to Home Assistant:

1. **Enable MQTT publishing:**
   ```python
   MQTT_ENABLED = True
   MQTT_BROKER = "homeassistant.local"
   MQTT_TOPIC_PREFIX = "netalertx"
   ```

2. **Use REST API:**
   ```python
   API_ENABLED = True
   # Access at http://[IP]:20212/graphql
   ```

### Custom Notifications

Configure various notification methods:

```python
# NTFY.sh
NTFY_ENABLED = True
NTFY_URL = "https://ntfy.sh"
NTFY_TOPIC = "your-topic"

# Pushover
PUSHOVER_ENABLED = True
PUSHOVER_TOKEN = "your-app-token"
PUSHOVER_USER = "your-user-key"

# Webhooks
WEBHOOK_ENABLED = True
WEBHOOK_URL = "https://your-webhook-url"
```

## 📁 File Structure

```
proxmox-netalertx-deploy/
├── deploy-netalertx.sh           # Main deployment script
├── install-netalertx.sh          # Container installation script
├── lxc-config-template.conf      # LXC configuration templates
├── README.md                     # This documentation
├── config/
│   ├── netalertx.env             # Environment variables template
│   └── app.conf.template         # NetAlertX configuration template
└── scripts/
    └── cleanup.sh                # Maintenance and cleanup utilities
```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request with detailed description

### Development Setup

```bash
# Clone for development
git clone <repository-url>
cd proxmox-netalertx-deploy

# Create test environment
# ... test your changes
```

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [NetAlertX](https://github.com/jokob-sk/NetAlertX) - The excellent network monitoring tool
- [Proxmox VE](https://www.proxmox.com/) - Virtualization platform
- Community contributors and testers

## 📞 Support

For support and questions:

1. **Check this documentation** for common solutions
2. **Review NetAlertX documentation** at [https://jokob-sk.github.io/NetAlertX/](https://jokob-sk.github.io/NetAlertX/)
3. **Search existing issues** in the project repository
4. **Create a new issue** with detailed logs and configuration

---

**Note**: This deployment script supports multiple Ubuntu versions (22, 24) and deployment targets (development, production) as specified in the user requirements. The interactive installer provides guided setup while maintaining full automation capabilities.
