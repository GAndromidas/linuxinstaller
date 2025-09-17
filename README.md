# Archinstaller: Comprehensive Arch Linux Post-Installation Script

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

---

## 🎬 Demo

![archinstaller](https://github.com/user-attachments/assets/7a2d86b9-5869-4113-818e-50b3039d6685)

---

## 🚀 Overview

**Archinstaller** is a comprehensive, automated post-installation script for Arch Linux and compatible distributions (including **CachyOS**) that transforms your fresh installation into a fully configured, optimized system. It handles everything from system preparation to desktop environment customization, security hardening, and robust dual-boot support.

### ✨ Key Features

- **🔧 Three Installation Modes**: Standard (complete setup), Minimal (essential tools), Custom (interactive selection)
- **🖥️ Smart DE Detection**: Automatic detection and optimization for KDE, GNOME, Cosmic, and fallback support
- **🐧 CachyOS Compatibility**: Native support with smart component skipping, preserves optimizations, replaces fastfetch config
- **🎮 Gaming Mode**: Works on both Arch and CachyOS with full gaming package support
- **🔒 Security Hardening**: Fail2ban, UFW/Firewalld, and comprehensive system service configuration
- **⚡ Performance Tuning**: Intelligent ZRAM setup, Plymouth boot screen, and system optimizations
- **📦 Multi-Source Packages**: Pacman, AUR (auto-detects helper), and Flatpak integration with YAML-driven configuration
- **🎨 Beautiful UI**: Custom terminal interface with gum styling, progress tracking, and comprehensive error handling
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
**AUR**: heroic-games-launcher-bin
**Flatpak**: com.vysp3r.ProtonPlus

---

## 🔧 System Optimizations & Features

### **Performance Enhancements**
- **Pacman Optimization**: 10 parallel downloads, color output, ILoveCandy, VerbosePkgLists
- **Multilib Repository**: Automatically enabled for 32-bit application support
- **Intelligent ZRAM**: Dynamic sizing based on available RAM with zstd compression
- **CPU Microcode**: Automatic Intel/AMD detection and installation
- **Kernel Headers**: Automatic installation for all installed kernels (linux, linux-lts, linux-zen, linux-hardened)
- **Mirror Optimization**: rate-mirrors integration for fastest mirror selection
- **SSD Optimization**: Automatic fstrim execution on SSD detection

### **Security Hardening**
- **Fail2ban**: SSH protection with 30-minute bans after 3 failed attempts
- **Firewall**: Auto-detects and configures UFW or Firewalld with SSH access
- **KDE Connect**: Automatic port configuration (1714-1764) if KDE Connect is installed
- **System Services**: Comprehensive service enablement and configuration

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
- **CachyOS Integration**: Interactive Fish→ZSH conversion with user choice or Fish enhancement
- **Starship**: Beautiful, fast prompt with system information
- **Enhanced Navigation**: zoxide for smart directory jumping
- **System Information**: fastfetch with custom configuration
- **Aliases**: Comprehensive system maintenance and navigation aliases
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

## 🐧 CachyOS Compatibility

**Archinstaller** provides native **CachyOS** support with smart compatibility:

### **What Gets Skipped** (Preserves CachyOS optimizations)
- **Graphics Drivers**: CachyOS manages these with optimized settings
- **ZRAM Configuration**: CachyOS has optimized ZRAM setup  
- **Microcode**: CachyOS handles automatic microcode updates
- **Bootloader Config**: CachyOS manages GRUB/systemd-boot optimally
- **AUR Helper Install**: Uses existing CachyOS helper (yay/paru/trizen)
- **Kernel/Repository Changes**: Preserves CachyOS kernels and repos

### **What Gets Enhanced**
- **Fastfetch Config**: Always replaces with archinstaller's custom config
- **Gaming Mode**: All gaming apps installed same as Arch Linux
- **Shell Choice**: Convert Fish→ZSH or enhance existing Fish
- **System Services**: Only enables what CachyOS hasn't configured
- **Applications**: Full package installation with smart duplicate detection

---

## 🎨 User Experience

### **Beautiful Interface**
- **gum Integration**: Modern terminal UI with styled prompts and progress indicators
- **Progress Tracking**: Real-time installation progress with step-by-step feedback
- **Error Handling**: Comprehensive error collection with detailed reporting
- **ASCII Art**: Beautiful Arch Linux branding throughout the installation
- **Color Coding**: Intuitive color-coded status messages for easy understanding

### **Installation Process**
1. **System Requirements**: Checks Arch Linux, internet connectivity, disk space, and user privileges
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
install.sh           - Main orchestration script with beautiful UI
scripts/common.sh    - Shared functions, colors, and utilities
scripts/system_preparation.sh - System updates and core package installation
scripts/shell_setup.sh        - ZSH, Oh-My-Zsh, and shell configuration
scripts/plymouth.sh           - Boot screen setup
scripts/yay.sh               - AUR helper installation
scripts/programs.sh          - Application installation with DE detection
scripts/gaming_mode.sh       - Gaming tools and performance tweaks
scripts/bootloader_config.sh - Bootloader detection and configuration
scripts/fail2ban.sh          - SSH security hardening
scripts/system_services.sh   - Service management and GPU drivers
scripts/maintenance.sh       - Final cleanup and optimization
```

### **Configuration Files**
```
configs/.zshrc          - Custom ZSH configuration with aliases
configs/starship.toml   - Starship prompt configuration
configs/MangoHud.conf   - Gaming performance overlay settings
configs/config.jsonc    - Fastfetch system information display
configs/kglobalshortcutsrc - KDE global shortcuts
configs/programs.yaml   - Complete package lists and desktop environment mappings
```

---

## 🚀 Quick Start

### Prerequisites
- Fresh Arch Linux installation **or CachyOS**
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
5. **Final Configuration**: Bootloader, security, and service setup
6. **System Reboot**: Automatic cleanup and reboot prompt

## 📋 Detailed Installation Flow

### **10 Installation Steps:**

**Step 1: System Preparation** 📦
- Updates package lists and mirrors
- Installs helper utilities (base-devel, curl, git, fastfetch, etc.)
- Configures pacman.conf optimizations (CachyOS: skipped)
- Installs CPU microcode (Intel/AMD) (CachyOS: skipped)
- Installs kernel headers for all detected kernels

**Step 2: Shell Setup** 🐚
- **Arch Linux**: Installs ZSH with Oh-My-Zsh, plugins, and Starship prompt
- **CachyOS**: Interactive choice between Fish→ZSH conversion or Fish enhancement

**Step 3: Plymouth Setup** 🎨
- Sets up beautiful boot screen with Arch logo
- Configures kernel parameters and initramfs
- **CachyOS**: Completely skipped (preserves CachyOS Plymouth)

**Step 4: AUR Helper Setup** 📦
- **Arch Linux**: Builds and installs yay from source
- **CachyOS**: Detects and uses existing AUR helper (yay/paru/trizen)

**Step 5: Programs Installation** 🖥️
- Installs packages based on selected mode (Standard/Minimal/Custom)
- Desktop environment specific applications (KDE/GNOME/Cosmic)
- Essential tools, browsers, media players, development tools
- AUR packages via detected helper
- Flatpak applications

**Step 6: Gaming Mode** 🎮
- **Optional**: Interactive gaming tools setup
- Installs Discord, Steam, Lutris, MangoHud, GameMode
- Configures MangoHud performance overlay
- Adds Heroic Games Launcher, ProtonPlus via AUR/Flatpak

**Step 7: Bootloader Configuration** 🔧
- **Arch Linux**: Full GRUB/systemd-boot configuration with Plymouth integration
- **CachyOS**: Completely skipped (preserves CachyOS bootloader setup)
- Windows dual-boot detection and configuration
- Fastfetch configuration (always replaced with archinstaller version)

**Step 8: Fail2ban Setup** 🛡️
- Installs and configures SSH protection
- Sets up 30-minute bans after 3 failed login attempts
- Configures systemd backend for log monitoring

**Step 9: System Services** ⚙️
- **Arch Linux**: Full firewall setup (UFW), ZRAM configuration, GPU drivers
- **CachyOS**: Conservative approach - only enables what CachyOS hasn't configured
- Enables essential services (SSH, Bluetooth, fstrim, etc.)
- Configures power management and system optimization

**Step 10: Maintenance** 🧹
- Cleans package caches (pacman, AUR helper, Flatpak)
- Removes orphaned packages and temporary files
- Updates mirror lists with rate-mirrors
- Final system optimization and sync

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
Each installation step is a separate script in `scripts/` directory. Modify the relevant script for custom behavior.

### Desktop Environment Support
Add new desktop environments by extending the `desktop_environments` section in `programs.yaml` and updating the detection logic in `programs.sh`.

### Gaming Mode Customization
Modify `scripts/gaming_mode.sh` to add or remove gaming applications and configurations.

---

## ⚠️ Important Notes

- **Run as regular user**: Never run as root - the script will check and exit
- **Fresh installation recommended**: Designed for post-installation setup on Arch Linux or CachyOS
- **Internet required**: All packages are downloaded during installation
- **Reboot recommended**: Many optimizations require a restart to take effect
- **Non-destructive**: Script preserves existing configurations when possible
- **CachyOS users**: Your optimizations and Plymouth setup are preserved; you choose how to handle Fish shell

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
