# Archinstaller: Comprehensive Arch Linux Post-Installation Script

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

---

## 🎬 Demo

![archinstaller](https://github.com/user-attachments/assets/7a2d86b9-5869-4113-818e-50b3039d6685)

---

## 🚀 Overview

**Archinstaller** is a comprehensive, automated post-installation script for Arch Linux that transforms your fresh installation into a fully configured, optimized system. It handles everything from system preparation to desktop environment customization, security hardening, and robust dual-boot support.

### ✨ Key Features

- **🔧 Three Installation Modes**: Standard (complete setup), Minimal (essential tools), Custom (interactive selection)
- **🖥️ Smart DE Detection**: Automatic detection and optimization for KDE, GNOME, Cosmic, and fallback support
- **🎮 Optional Gaming Mode**: Interactive setup for comprehensive gaming tools and performance optimization
- **🔒 Security Hardening**: Fail2ban, UFW/Firewalld, and comprehensive system service configuration
- **Performance Tuning**: Smart ZRAM profiles (gaming vs regular), Plymouth boot screen, and system optimizations
- **📦 Multi-Source Packages**: Pacman, AUR (via Paru), and Flatpak integration with YAML-driven configuration
- **🎨 Beautiful UI**: Custom terminal interface with gum styling, progress tracking, and comprehensive error handling
- **🔒 SSH Security**: Optional SSH hardening with customizable security settings
- **🧭 Dual Bootloader Support**: Automatically detects and configures both GRUB and systemd-boot with Windows dual-boot automation
- **🪟 Windows Dual-Boot Intelligence**: Detects Windows installations, manages EFI files, configures boot entries, and ensures compatibility
- **🎯 GPU Auto-Detection**: Intelligent AMD/Intel/NVIDIA driver installation with Vulkan support and VM detection

---

## 🛠️ Installation Modes

### 1. **Standard Mode** 🎯 (Complete Setup)
Full-featured installation with all recommended packages and optimizations:
- **Pacman**: 25+ core packages (browsers, utilities, fonts, development tools)
- **Essential**: 7 productivity applications (GIMP, KDENlive, OpenRGB, Timeshift, VLC, etc.)
- **AUR**: 8 applications (Dropbox, Spotify, Stremio, Ventoy, RustDesk, etc.)
- **Flatpaks**: Desktop environment-specific applications
- **Perfect for**: Users who want a complete, ready-to-use system

### 2. **Minimal Mode** ⚡ (Essential Only)
Lightweight setup with core utilities only:
- **Pacman**: Same 25+ core packages as Standard
- **Essential**: 3 essential applications (Timeshift, VLC, VLC plugins)
- **AUR**: 4 essential applications (OnlyOffice, Rate-Mirrors, RustDesk, Stremio)
- **Flatpaks**: Minimal DE-specific applications
- **Perfect for**: Users who prefer a clean, essential setup or have limited resources

### 3. **Custom Mode** 🎛️ (Interactive Selection)
Interactive package selection with detailed descriptions:
- **Whiptail GUI**: User-friendly interface for package selection
- **Smart Categories**: Auto-selected core packages + optional selections
- **Package Descriptions**: Detailed information for each optional package
- **Preview Summary**: Shows total packages before installation
- **Perfect for**: Advanced users who want granular control

---

## 🖥️ Desktop Environment Support

### **KDE Plasma** 🟦
- **Installs**: KDE-specific utilities (KDE Connect, Spectacle, Okular, QBittorrent, Kvantum)
- **Removes**: Conflicting packages (htop - replaced by btop)
- **Flatpaks**: Desktop environment integration, GearLever
- **Shortcuts**: Custom global shortcuts configuration

### **GNOME** 🟪
- **Installs**: GNOME utilities (GNOME Tweaks, Transmission GTK, Seahorse, dconf-editor)
- **Removes**: Bloatware (Epiphany, GNOME Contacts, Maps, Music, Tour, Totem, Snapshot)
- **Flatpaks**: Extension Manager, Desktop environment, GearLever
- **Theme**: ADW GTK theme integration

### **Cosmic** 🟨
- **Installs**: Cosmic-specific utilities and power management
- **Removes**: Conflicting packages (htop)
- **Flatpaks**: CosmicTweaks, Desktop environment, GearLever
- **Optimization**: Basic Cosmic desktop optimization

### **Other DEs/WMs** 🔧
- **Generic Support**: Works with any desktop environment or window manager
- **Minimal Packages**: Essential utilities without DE-specific conflicts
- **Flatpak Support**: GearLever for application management

---

## 📦 Complete Package Breakdown

### **Core Pacman Packages** (All Modes)
```
System Tools    : android-tools, bleachbit, btop, gnome-disk-utility, hwinfo, inxi, ncdu
Network         : net-tools, speedtest-cli, sshfs, samba
Development     : git (included in helpers), base-devel (included in helpers)
Media           : chromium, firefox, vlc (in essential)
Utilities       : bat, cmatrix, dosfstools, expac, sl, unrar
Fonts           : noto-fonts-extra, ttf-hack-nerd, ttf-liberation
System          : fwupd, xdg-desktop-portal-gtk
```

### **Helper Utilities** (Installed First)
```
base-devel, bc, bluez-utils, cronie, curl, eza, fastfetch, figlet, flatpak, 
fzf, git, openssh, pacman-contrib, plymouth, rsync, ufw, zoxide, 
zsh, zsh-autosuggestions, zsh-syntax-highlighting, starship, zram-generator
```

### **Essential Packages**
**Standard Mode**: filezilla, gimp, kdenlive, openrgb, timeshift, vlc, vlc-plugins-all  
**Minimal Mode**: timeshift, vlc, vlc-plugins-all

### **AUR Packages**
**Standard Mode**: dropbox, onlyoffice-bin, rate-mirrors-bin, rustdesk-bin, spotify, stremio, ventoy-bin, via-bin  
**Minimal Mode**: onlyoffice-bin, rate-mirrors-bin, rustdesk-bin, stremio

### **Gaming Mode Packages** (Optional)
**Pacman**: discord, gamemode, lib32-gamemode, lutris, mangohud, lib32-mangohud, obs-studio, steam, wine  
**AUR**: heroic-games-launcher-bin (installed via Paru)
**Flatpak**: com.vysp3r.ProtonPlus

---

## 🔧 System Optimizations & Features

### **Performance Enhancements**
- **Pacman Optimization**: Parallel downloads and color output enabled
- **Multilib Repository**: Automatically enabled for 32-bit application support
- **Smart ZRAM System**: Context-aware ZRAM configuration with gaming vs regular profiles
  - **Gaming Profile**: CachyOS-style aggressive tuning (150-180 swappiness, kernel optimizations)
  - **Regular Profile**: Balanced desktop performance (80-100 swappiness, conservative settings)
- **CPU Microcode**: Automatic Intel/AMD detection and installation
- **Kernel Headers**: Automatic installation for all installed kernels
- **AUR Helper**: Modern Paru AUR helper (precompiled binary installation)
- **Mirror Optimization**: rate-mirrors integration for fastest mirror selection

### **Security Hardening**
- **Fail2ban**: SSH protection with 30-minute bans after 3 failed attempts
- **Firewall**: Auto-detects and configures UFW with SSH access
- **SSH Hardening**: Optional SSH security configuration (disabled root login, connection limits, idle timeouts)
- **KDE Connect**: Automatic port configuration (1714-1764) if KDE Connect is installed
- **System Services**: Comprehensive service management and configuration

### **Boot Experience**
- **Plymouth**: Beautiful boot screen with automatic configuration
- **Dual Bootloader Support**: 
  - **systemd-boot**: Quiet boot, 3s timeout, console-mode max, removes fallback entries
  - **GRUB**: Plymouth integration, 3s timeout, saves default entry, removes fallback images
- **Btrfs Integration**: Automatic grub-btrfs installation and configuration for snapshot support
- **Windows Dual-Boot**: 
  - Detects Windows installations automatically
  - Copies Microsoft EFI files if needed (systemd-boot)
  - Adds Windows entries to boot menu (both bootloaders)
  - Sets hardware clock to local time for compatibility
  - Installs ntfs-3g for NTFS partition access

### **Shell Configuration**
- **ZSH**: Default shell with Oh-My-Zsh framework
- **Starship**: Beautiful, fast prompt with system information
- **Enhanced Navigation**: zoxide for smart directory jumping
- **System Information**: fastfetch with custom configuration
- **Aliases**: Comprehensive system maintenance and navigation aliases (using Paru)
- **Plugins**: Git integration, FZF fuzzy finding, autosuggestions, syntax highlighting

### **GPU Driver Intelligence**
- **AMD**: Mesa, AMDGPU, Vulkan support with 32-bit libraries
- **Intel**: Mesa, Intel Vulkan, hardware acceleration libraries  
- **NVIDIA**: 
  - Auto-detects GPU generation (Turing+, Maxwell/Pascal, Kepler, Fermi, Tesla)
  - Recommends appropriate driver (nvidia-open-dkms for newer, nvidia for older)
  - Offers Nouveau alternative for legacy cards
  - Includes Vulkan and 32-bit library support
- **VM Detection**: Installs guest utilities (qemu-guest-agent, spice-vdagent, xf86-video-qxl) when virtualization is detected

---

## 🎨 User Experience

### **Beautiful Interface**
- **gum Integration**: Modern terminal UI with styled prompts and progress indicators
- **Progress Tracking**: Real-time installation progress with step-by-step feedback
- **Error Handling**: Comprehensive error collection with detailed reporting
- **ASCII Art**: Beautiful Arch Linux branding throughout the installation
- **Color Coding**: Intuitive color-coded status messages for easy understanding

### **Installation Process**
1. **System Requirements**: Checks Arch Linux, internet connectivity, disk space, and prerequisites  
2. **Interactive Menu**: Clean mode selection with descriptions
3. **10 Installation Steps**: Each step clearly labeled with progress tracking
4. **Error Recovery**: Non-critical errors don't stop installation; comprehensive error reporting
5. **Final Summary**: Complete breakdown of installed/removed packages and any issues
6. **Reboot Management**: Intelligent reboot prompt with system preparation

---

## 🧩 Modular Architecture

### **YAML-Driven Configuration**
- **programs.yaml**: All package lists, descriptions, and desktop environment mappings
- **Easy Customization**: Add/remove packages by editing YAML configuration
- **Mode Support**: Separate package lists for default, minimal, and desktop environments
- **Scalable**: Easy to extend with new desktop environments or package categories

### **Modular Scripts**
```
install.sh                    - Main orchestration script with beautiful UI
scripts/common.sh            - Shared functions, colors, and utilities (enhanced)
scripts/system_setup.sh      - System updates, core packages, and Paru AUR helper setup
scripts/user_environment.sh  - ZSH, Oh-My-Zsh, and shell configuration
scripts/boot_setup.sh        - Plymouth boot screen and bootloader configuration
scripts/applications.sh      - Application installation with DE detection
scripts/gaming_setup.sh      - Gaming tools and performance tweaks
scripts/security_setup.sh    - Fail2ban, firewall, and SSH security hardening
scripts/system_services.sh   - Service management, smart ZRAM profiles, and GPU drivers
scripts/maintenance.sh       - Final cleanup and optimization
```

### **Configuration Files**
```
configs/.zshrc               - Custom ZSH configuration with aliases
configs/starship.toml        - Starship prompt configuration
configs/MangoHud.conf        - Gaming performance overlay settings
configs/config.jsonc         - Fastfetch system information display
configs/kglobalshortcutsrc   - KDE global shortcuts
configs/programs.yaml        - YAML-driven package configuration
```

---

## 🚀 Quick Start

### Prerequisites
- Fresh Arch Linux installation
- Internet connection  
- Regular user account with sudo privileges
- At least 2GB free disk space

### Installation
```bash
# Clone the repository
git clone https://github.com/gandromidas/archinstaller && cd archinstaller

# Make executable and run
chmod +x install.sh
./install.sh
```

### What Happens Next
1. **System Check**: Validates prerequisites automatically
2. **Mode Selection**: Choose your installation approach
3. **Automated Installation**: Sit back and let the script work (10-20 minutes)
4. **Gaming Setup**: Optional gaming tools installation
5. **Security Configuration**: Optional SSH hardening and firewall setup
6. **Final Configuration**: Bootloader, services, and system optimization
7. **System Reboot**: Automatic cleanup and reboot prompt

---

## 🔧 Customization

### Adding Packages
Edit `configs/programs.yaml` to add packages to any mode or desktop environment:
```yaml
essential:
  default:
    - name: "your-package"
      description: "Package description"
```

### Modifying Installation Logic
Each installation step uses consolidated scripts in `scripts/` directory:
- **System foundation**: `system_setup.sh` (system prep + Paru AUR helper)
- **User experience**: `user_environment.sh` (ZSH shell and configs)
- **Boot configuration**: `boot_setup.sh` (Plymouth + bootloader configuration)
- **Security**: `security_setup.sh` (fail2ban + firewall + optional SSH hardening)

### Desktop Environment Support
Add new desktop environments by extending the `desktop_environments` section in `programs.yaml` and updating the detection logic in `applications.sh`.

### Gaming Mode Customization
Modify `scripts/gaming_setup.sh` to add or remove gaming applications and configurations.

---

## ⚠️ Important Notes

- **Run as regular user**: Never run as root - the script will check and exit
- **Fresh installation recommended**: Designed for post-installation setup  
- **Internet required**: All packages are downloaded during installation
- **Paru AUR helper**: Modern replacement for yay with better performance
- **SSH hardening**: Optional security feature - prompts before applying
- **Reboot recommended**: Many optimizations require a restart to take effect
- **Non-destructive**: Script preserves existing configurations when possible

---

## 🤝 Contributing

This project is designed to be easily extensible. To contribute:

1. **Package additions**: Update `configs/programs.yaml`
2. **New features**: Add scripts to `scripts/` directory
3. **Desktop environments**: Extend DE detection and package selection
4. **Configurations**: Add config files to `configs/` directory

---

## 📄 License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

---

**Transform your Arch Linux installation into a powerhouse! 🚀**