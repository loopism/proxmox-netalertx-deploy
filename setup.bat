@echo off
REM NetAlertX Proxmox Deployment Setup Script for Windows
REM This script prepares the deployment files for use on a Proxmox host

echo NetAlertX Proxmox LXC Deployment Setup
echo =====================================
echo.
echo This script prepares the deployment files for transfer to your Proxmox host.
echo.
echo Files created:
echo - deploy-netalertx.sh       : Main deployment script
echo - install-netalertx.sh      : Container installation script  
echo - scripts/cleanup.sh        : Maintenance and cleanup utilities
echo - config/netalertx.env      : Environment configuration template
echo - config/app.conf.template  : NetAlertX configuration template
echo - README.md                 : Complete documentation
echo.
echo Next steps:
echo 1. Copy these files to your Proxmox host
echo 2. Make scripts executable: chmod +x *.sh scripts/*.sh
echo 3. Run: ./deploy-netalertx.sh
echo.
echo For detailed instructions, see README.md
echo.
pause
