# 🚀 Arch Installer - Usage Guide

## 📋 Quick Start

### Prerequisites
- Fresh Arch Linux installation
- Internet connection
- At least 2GB free disk space
- Regular user account (not root)

### Installation Steps

1. **Download the installer:**
   ```bash
   git clone https://github.com/yourusername/archinstaller.git
   cd archinstaller
   ```

2. **Make it executable:**
   ```bash
   chmod +x install.sh
   ```

3. **Run the installer:**
   ```bash
   ./install.sh
   ```

4. **Follow the prompts:**
   - Choose your installation mode (Default/Minimal/Custom)
   - Enter your password when prompted
   - Wait for the installation to complete (10-20 minutes)
   - Reboot when finished

## 🎯 Installation Modes

### Default Mode (Advanced Users)
- **Best for:** Advanced users who want all packages and tools
- **What it includes:**
  - Complete desktop environment setup
  - All applications and utilities
  - Security features
  - Performance optimizations
  - Optional gaming tools
  - Additional tools (GIMP, Kdenlive, FileZilla, etc.)

### Minimal Mode (Recommended for New Users)
- **Best for:** New users and those who want a clean, essential setup
- **What it includes:**
  - Basic desktop environment
  - Essential tools only (LibreOffice, VLC, Timeshift)
  - Security features
  - Performance optimizations

### Custom Mode
- **Best for:** Advanced users who want full control
- **What it includes:**
  - Interactive package selection
  - Choose what to install
  - Full customization options

## 🎮 Gaming Mode

When prompted, you can choose to install gaming tools:
- **Steam** - Popular gaming platform
- **Discord** - Gaming chat application
- **Lutris** - Game manager and launcher
- **Wine** - Run Windows games
- **Heroic Games Launcher** - Epic Games Store alternative
- **ProtonPlus** - Steam Proton management tool

## 🔧 What Gets Installed

### System Tools
- **ZSH Shell** - Enhanced command line with autocompletion
- **Starship** - Beautiful command prompt
- **Yay** - AUR package manager
- **UFW** - Firewall
- **Fail2ban** - SSH protection
- **ZRAM** - Memory compression

### Desktop Environment
- **KDE Plasma** - Modern desktop environment
- **GNOME** - Clean and simple desktop
- **Cosmic** - System76's desktop environment

### Applications
- **File Manager** - Dolphin (KDE) / Nautilus (GNOME)
- **Web Browser** - Firefox
- **Terminal** - Konsole (KDE) / GNOME Terminal
- **Text Editor** - Kate (KDE) / Gedit (GNOME)
- **Media Player** - VLC
- **Image Viewer** - Gwenview (KDE) / Eye of GNOME

## 🛡️ Security Features

- **Firewall** - UFW with sensible defaults
- **SSH Protection** - Fail2ban to prevent brute force attacks
- **System Updates** - Automatic security updates

## ⚡ Performance Optimizations

- **ZRAM** - Memory compression for better performance
- **Plymouth** - Beautiful boot screen
- **System Services** - Optimized service configuration

## 🔄 After Installation

1. **Reboot your system** when prompted
2. **Log in** to your desktop environment
3. **Explore** your new system!
4. **Install additional software** using your package manager

## 🆘 Troubleshooting

### Common Issues

**"Permission denied" error:**
- Make sure you're not running as root
- Run: `chmod +x install.sh`

**"No internet connection" error:**
- Check your network connection
- Try: `ping archlinux.org`

**"Insufficient disk space" error:**
- Free up at least 2GB of space
- Check with: `df -h`

**Installation fails:**
- Check the error messages
- Try running the installer again
- Most errors are non-critical

### Getting Help

- Check the error messages in the terminal
- Review the installation logs
- Try running the installer again
- Ask for help in the Arch Linux forums

## 🎉 Enjoy Your New System!

Your Arch Linux system is now fully configured and ready to use. You have:
- A beautiful desktop environment
- All essential applications
- Security features enabled
- Performance optimizations
- Optional gaming tools

Welcome to the Arch Linux community! 🐧 