# Installation Guide

This guide will walk you through installing LinuxInstaller on your Linux system.

## 📋 Prerequisites

### System Requirements
- **Operating System**: Fresh installation of Arch Linux, Fedora, Debian, or Ubuntu
- **Privileges**: Root access (sudo) for system modifications
- **Internet**: Active internet connection for package downloads
- **Storage**: Minimum 2GB free space (4GB recommended)
- **Terminal**: Color support recommended for best experience

### Supported Versions
- **Arch Linux**: Rolling release
- **Fedora**: 38, 39, 40
- **Debian**: 11 (Bullseye), 12 (Bookworm)
- **Ubuntu**: 20.04 LTS, 22.04 LTS, 24.04 LTS

## 🚀 Installation Methods

### Method 1: One-Line Installation (Recommended)

```bash
# Download and run in one command
wget -qO- https://raw.githubusercontent.com/GAndromidas/linuxinstaller/main/install.sh | bash
```

**What this does:**
- Downloads the installation script
- Makes it executable
- Runs it with sudo automatically
- Starts the interactive installation process

### Method 2: Local Installation

```bash
# Clone the repository
git clone https://github.com/GAndromidas/linuxinstaller.git
cd linuxinstaller

# Make executable and run
chmod +x install.sh
sudo ./install.sh
```

## 🎯 Installation Process

### Step 1: Welcome Screen
When you run the script, you'll see a beautiful ASCII banner and be prompted to select an installation mode.

### Step 2: Choose Installation Mode

#### Standard Mode (Recommended)
- Complete desktop environment setup
- All recommended packages
- Gaming suite option
- Full development environment

#### Minimal Mode
- Essential tools only
- Lightweight installation
- Perfect for VMs and containers
- Optional gaming packages

#### Server Mode
- Headless server configuration
- Security hardening
- No desktop environment
- Optimized for remote access

### Step 3: Gaming Suite (Optional)
If you choose Standard or Minimal mode, you'll be asked if you want to install the gaming suite:
- Steam installation and configuration
- Wine setup for Windows games
- GPU driver detection and installation
- Performance monitoring tools (MangoHud)

### Step 4: Installation Progress
The script will:
1. Update system repositories
2. Install selected packages
3. Configure security features
4. Optimize performance
5. Set up desktop environment
6. Install gaming packages (if selected)
7. Display installation summary

## 🔧 Command Line Options

```bash
sudo ./install.sh [OPTIONS]

Options:
  -h, --help      Show help message and usage
  -v, --verbose   Enable detailed output and logging
  -d, --dry-run   Preview changes without applying them
```

### Using Dry Run Mode

```bash
# See what would be installed without making changes
sudo ./install.sh --dry-run

# Combine with verbose for detailed preview
sudo ./install.sh --dry-run --verbose
```

## 📊 What Gets Installed

### All Modes
- **Security**: UFW firewall, fail2ban, SSH hardening
- **Performance**: CPU governor tuning, ZRAM, filesystem optimization
- **Shell**: Zsh with autosuggestions, Starship prompt, Fastfetch
- **Development**: Git, build tools, package managers

### Standard Mode Additional
- **Desktop**: Full KDE Plasma or GNOME setup
- **Applications**: Browsers, media players, office tools
- **Gaming**: Optional Steam, Wine, GPU drivers
- **Themes**: Consistent theming across applications

### Server Mode Additional
- **Server Tools**: SSH server, monitoring tools
- **Security**: Additional hardening for remote access
- **Maintenance**: Automated update scripts

## ⚠️ Important Notes

### NVIDIA GPU Users
If you have an NVIDIA GPU:
1. LinuxInstaller will **not** install NVIDIA drivers automatically
2. After installation, install NVIDIA drivers manually:
   ```bash
   # Arch Linux
   sudo pacman -S nvidia nvidia-utils

   # Ubuntu/Debian
   sudo apt install nvidia-driver

   # Fedora
   sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
   ```
3. Reboot your system after driver installation

### Existing Configurations
- LinuxInstaller **does not create backups** of existing configurations
- Review your current setup before running
- The script modifies system files directly

### Internet Connection
- Installation requires a stable internet connection
- Downloads can be several GB depending on selected packages
- Check your connection speed before starting

## 🔄 Post-Installation

### First Reboot (Recommended)
```bash
sudo reboot
```

### Verify Installation
```bash
# Check if services are running
systemctl status ufw
systemctl status fail2ban

# Verify shell changes
echo $SHELL  # Should show /usr/bin/zsh

# Test GPU drivers (if applicable)
nvidia-smi  # For NVIDIA
vulkaninfo  # For AMD/Intel
```

### Optional Configuration
- Customize your shell configuration in `~/.zshrc`
- Adjust Starship prompt in `~/.config/starship.toml`
- Configure Fastfetch display in `~/.config/fastfetch/config.jsonc`

## 🆘 Troubleshooting Installation

### Script Won't Start
```bash
# Check if you have sudo access
sudo whoami

# Verify internet connection
ping -c 3 google.com

# Check system requirements
uname -a  # Should show Linux
```

### Installation Fails
- Check the error messages carefully
- Most failures are due to network issues or package conflicts
- Try running with `--verbose` for detailed output
- Check the [[Troubleshooting|Troubleshooting]] page for specific errors

### Need Help?
- Check the [[FAQ|FAQ]] for common questions
- Search existing [GitHub Issues](https://github.com/GAndromidas/linuxinstaller/issues)
- Create a new issue if you can't find a solution

## 🎉 Success!

Congratulations! You've successfully installed LinuxInstaller. Your Linux system is now optimized, secure, and ready for development work. Enjoy your beautiful, powerful Linux environment! 🚀</content>
<parameter name="filePath">linuxinstaller/wiki/Installation-Guide.md