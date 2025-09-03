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

- **🔧 Three Installation Modes**: Standard (full setup), Minimal (core utilities - recommended for new users), Custom (interactive selection)
- **🖥️ Smart DE Detection**: Automatic detection and optimization for KDE, GNOME, Cosmic, and fallback support
- **🎮 Optional Gaming Mode**: Interactive Y/n prompt for comprehensive gaming setup (Discord, GameMode, Heroic Games Launcher, Lutris, MangoHud, OBS Studio, ProtonPlus, Steam, and Wine)
- **🔒 Security Hardening**: Fail2ban, UFW/Firewalld, and system service configuration
- **⚡ Performance Tuning**: ZRAM, Plymouth boot screen, and system optimizations
- **📦 Multi-Source Packages**: Pacman, AUR (via YAY), and Flatpak integration
- **🎨 Beautiful UI**: Custom terminal interface with progress tracking and error handling
- **🧭 Dual Bootloader Support**: Automatically detects and configures both GRUB and systemd-boot, including kernel parameters, Plymouth, and Btrfs integration
- **🪟 Windows Dual-Boot Automation**: Detects Windows installations, copies EFI files if needed, adds Windows to the boot menu for both GRUB and systemd-boot, and sets the hardware clock for compatibility
- **💾 NTFS Support**: Installs `ntfs-3g` automatically if Windows is detected, for seamless access to NTFS partitions

---

## 🧭 Bootloader & Windows Dual-Boot Support

- **Automatic Detection**: The installer detects whether your system uses GRUB or systemd-boot.
- **Configuration**: Sets kernel parameters, timeout, default entry, and console mode for the detected bootloader.
- **Plymouth**: Ensures splash and Plymouth are enabled for both bootloaders.
- **Btrfs**: If using GRUB and Btrfs, automatically installs and enables grub-btrfs for snapshot integration.
- **Windows Dual-Boot**:
  - Detects Windows installations.
  - For systemd-boot: finds and copies Microsoft EFI files from the Windows EFI partition if needed, then creates a loader entry.
  - For GRUB: enables os-prober, ensures Windows is in the boot menu.
  - Sets the hardware clock to local time for compatibility.
- **NTFS Support**: Installs `ntfs-3g` for NTFS access and os-prober compatibility.

---

## 🛠️ Installation Modes

### 1. **Standard Mode** 🎯 (Intermediate Users)
Complete setup with all recommended packages and optimizations:
- Full package suite (30+ Pacman packages, 6+ AUR packages)
- Desktop environment-specific optimizations
- Additional productivity and media applications
- Security hardening
- Performance tuning
- **Perfect for**: Intermediate users who want all packages and tools

### 2. **Minimal Mode** ⚡ (Recommended for New Users)
Lightweight setup with essential utilities:
- Core system utilities (30+ Pacman packages, 2 AUR packages)
- Basic desktop environment support
- Essential security features
- Minimal performance optimizations
- **Perfect for**: New users who want a clean, essential setup

### 3. **Custom Mode** 🎛️ (Advanced Users)
Interactive package selection with descriptions:
- Whiptail-based GUI for package selection
- Detailed package descriptions
- Granular control over installations
- Preview of total packages before installation
- **Auto-selected Pacman packages**: Core system packages are automatically included (no user choice needed)
- **Essential packages selection**: Choose productivity and media applications
- **AUR and Flatpak selection**: Select additional applications from AUR and Flatpak

---

## 🖥️ Desktop Environment Support

### **KDE Plasma** 🟦
- **Install**: KDE-specific utilities and optimizations
- **Remove**: Conflicting packages
- **Flatpaks**: Desktop environment, GearLever

### **GNOME** 🟪
- **Install**: GNOME-specific utilities and extensions
- **Remove**: Conflicting packages
- **Flatpaks**: Extension Manager, Desktop environment, GearLever

### **Cosmic** 🟨
- **Install**: Cosmic-specific utilities and tweaks
- **Remove**: Conflicting packages
- **Flatpaks**: Desktop environment, GearLever, CosmicTweaks

### **Other DEs/WMs** 🔧
- Falls back to minimal package set
- Generic optimizations
- Basic Flatpak support

---

## 📦 Package Categories

### **Pacman Packages (All Modes)**
- **Development**: `android-tools`
- **System Tools**: `bat`, `bleachbit`, `btop`, `gnome-disk-utility`, `hwinfo`, `inxi`, `ncdu`, `speedtest-cli`
- **Utilities**: `cmatrix`, `expac`, `net-tools`, `sl`, `unrar`
- **Media**: `chromium`, `firefox`, `noto-fonts-extra`, `ttf-hack-nerd`, `ttf-liberation`
- **System**: `dosfstools`, `fwupd`, `samba`, `sshfs`, `xdg-desktop-portal-gtk`

### **Essential Packages (Standard Mode)**
- **Productivity**: `filezilla`, `gimp`, `kdenlive`, `libreoffice-fresh`, `openrgb`, `timeshift`, `vlc`, `zed`

### **Essential Packages (Minimal Mode)**
- **Productivity**: `libreoffice-fresh`, `timeshift`, `vlc`

### **AUR Packages (Standard Mode)**
- **Cloud Storage**: `dropbox`
- **Media**: `spotify`, `stremio`
- **Utilities**: `ventoy-bin`, `via-bin`
- **Remote Access**: `rustdesk-bin`
- **Media**: `spotify`, `stremio`
- **Utilities**: `ventoy-bin`, `via-bin`
- **Remote Access**: `rustdesk-bin`

### **AUR Packages (Minimal Mode)**
- **Media**: `stremio`
- **Remote Access**: `rustdesk-bin`
- **Remote Access**: `rustdesk-bin`

### **Flatpak Applications**
- **Desktop Integration**: `io.github.shiftey.Desktop`
- **System Tools**: `it.mijorus.gearlever`, `dev.edfloreshz.CosmicTweaks`
- **Extensions**: `com.mattjakeman.ExtensionManager`

---

## 🔧 System Optimizations

### **Performance Enhancements**
- **ZRAM**: 50% RAM compression with zstd algorithm
- **Pacman Optimization**: Parallel downloads, color output, ILoveCandy
- **Mirror Optimization**: Fastest mirror selection via reflector
- **CPU Microcode**: Automatic Intel/AMD microcode installation
- **Kernel Headers**: Automatic installation for all installed kernels

### **Gaming Mode Features** (Optional)
- **Interactive Setup**: Y/n prompt with default "Yes" (press Enter to accept)
- **Performance Monitoring**: MangoHud for real-time system monitoring
- **GameMode**: Default GameMode installation (vanilla configuration)
- **Gaming Platforms**: Steam, Lutris, Discord, Heroic Games Launcher, OBS Studio
- **Compatibility**: Wine for Windows game compatibility
- **Streaming/Recording**: OBS Studio for content creation
- **Proton Management**: ProtonPlus for Wine/Proton version management
- **Hardware Support**: Works on any system (VM detection included)

### **Security Hardening**
- **Fail2ban**: SSH protection with 30-minute bans, 3 retry limit
- **Firewall**: UFW or Firewalld with SSH and KDE Connect support
- **System Services**: Automatic service enablement and configuration

---

## 🎨 User Experience

### **Shell Configuration**
- **ZSH**: Default shell with autosuggestions and syntax highlighting
- **Starship**: Beautiful, fast prompt with system information
- **Zoxide**: Smart directory navigation
- **Fastfetch**: System information display with custom configuration

### **Boot Experience**
- **Plymouth**: Beautiful boot screen with BGRT theme
- **Bootloader Support**: Automatic detection and configuration for both GRUB and systemd-boot
- **Splash Parameters**: Automatic kernel parameter configuration for both bootloaders
- **Initramfs**: Automatic rebuild with Plymouth hooks
- **Btrfs Integration**: Installs and enables grub-btrfs if using GRUB with a Btrfs root filesystem
- **Windows Dual-Boot**: Detects Windows installations, copies EFI files if needed, adds Windows to the boot menu for both GRUB and systemd-boot, and sets the hardware clock to local time for compatibility
- **NTFS Support**: Installs `ntfs-3g` for NTFS access and os-prober compatibility

### **Terminal Interface**
- **Progress Tracking**: Real-time installation progress
- **Error Handling**: Comprehensive error collection and reporting
- **Color Coding**: Intuitive color-coded status messages
- **ASCII Art**: Beautiful Arch Linux branding

---

## 🧩 Modular & YAML-Driven Design

Archinstaller is built for flexibility and easy customization:
- **YAML-based package management**: All package lists (Pacman, AUR, Flatpak) and descriptions are in `configs/programs.yaml`.
- **Desktop environment logic**: Packages and Flatpaks are selected based on your DE (KDE, GNOME, Cosmic, etc).
- **Modular scripts**: Each setup step is a separate script in `scripts/` (system prep, shell, Plymouth, programs, gaming, bootloader, fail2ban, services, maintenance).
- **All configuration in `configs/`**: Fastfetch, Starship, MangoHud, .zshrc, and more.
- **Optional Gaming Mode**: Fully modular, can be extended by editing `scripts/gaming_mode.sh`.

### 🛠 How to Add/Remove Packages or Customize
- **Edit `configs/programs.yaml`** to add/remove packages for any mode or DE.
- **Edit scripts in `scripts/`** to change install logic, add new steps, or customize Gaming Mode.
- **Edit config files in `configs/`** to change Fastfetch, Starship, MangoHud, or shell settings.

---

## 🚀 Quick Start

```bash
# Clone the repository
git clone [https://github.com/gandromidas/archinstaller](https://github.com/gandromidas/archinstaller) && cd archinstaller

# Make executable and run
chmod +x install.sh
./install.sh
