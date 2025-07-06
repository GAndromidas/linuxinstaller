# Archinstaller: Comprehensive Arch Linux Post-Installation Script

[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![Total Downloads](https://img.shields.io/github/downloads/GAndromidas/archinstaller/total.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)

---

## 🎬 Demo

[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

![Screenshot_20250707_020649](https://github.com/user-attachments/assets/732569f4-664d-44b7-97d2-6ae867495d25)

---

## 🚀 Overview

**Archinstaller** is a comprehensive, automated post-installation script for Arch Linux that transforms your fresh installation into a fully configured, optimized system. It handles everything from system preparation to desktop environment customization, gaming optimizations, security hardening, and robust dual-boot support.

### ✨ Key Features

- **🔧 Three Installation Modes**: Default (full setup), Minimal (core utilities), Custom (interactive selection)
- **🖥️ Smart DE Detection**: Automatic detection and optimization for KDE, GNOME, Cosmic, and fallback support
- **🎮 Optional Gaming Mode**: Interactive Y/n prompt for comprehensive gaming setup (MangoHud, GameMode, Steam, Lutris, Wine, Discord, Heroic Games Launcher, ProtonPlus)
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

### 1. **Default Mode** 🎯
Complete setup with all recommended packages and optimizations:
- Full package suite (30+ Pacman packages, 8+ AUR packages)
- Desktop environment-specific optimizations
- Gaming tools and optimizations
- Security hardening
- Performance tuning

### 2. **Minimal Mode** ⚡
Lightweight setup with essential utilities:
- Core system utilities (28 Pacman packages, 4 AUR packages)
- Basic desktop environment support
- Essential security features
- Minimal performance optimizations

### 3. **Custom Mode** 🎛️
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
- **Flatpaks**: Desktop environment, GearLever, ProtonUp-Qt

### **GNOME** 🟪
- **Install**: GNOME-specific utilities and extensions
- **Remove**: Conflicting packages  
- **Flatpaks**: Extension Manager, Desktop environment, GearLever, ProtonPlus

### **Cosmic** 🟨
- **Install**: Cosmic-specific utilities and tweaks
- **Remove**: Conflicting packages
- **Flatpaks**: Desktop environment, GearLever, ProtonPlus, CosmicTweaks

### **Other DEs/WMs** 🔧
- Falls back to minimal package set
- Generic optimizations
- Basic Flatpak support

---

## 📦 Package Categories

### **Pacman Packages (All Modes)**
- **Development**: `android-tools`, `git`, `base-devel`
- **System Tools**: `btop`, `hwinfo`, `inxi`, `gnome-disk-utility`
- **Utilities**: `bat`, `eza`, `fzf`, `zoxide`, `fastfetch`
- **Media**: `vlc`, `firefox`, `ttf-hack-nerd`, `ttf-liberation`
- **System**: `ufw`, `fail2ban`, `reflector`, `zram-generator`
- **Networking**: `openssh`, `sshfs`, `net-tools`, `samba`

*Note: Gaming packages (GameMode, MangoHud, Steam, etc.) are now part of the optional Gaming Mode*

### **Essential Packages (Default Mode)**
- **Productivity**: `libreoffice-fresh`, `gimp`, `kdenlive`
- **Media**: `vlc`, `timeshift`
- **Utilities**: `filezilla`

*Note: Gaming packages (Steam, Lutris, Discord, Wine) are now part of the optional Gaming Mode*

### **AUR Packages (Default Mode)**
- **Cloud**: `dropbox`
- **Media**: `spotify`, `stremio`
- **Utilities**: `ventoy-bin`, `visual-studio-code-bin`
- **Hardware**: `via-bin`

*Note: Gaming packages (Heroic Games Launcher) are now part of the optional Gaming Mode*

### **Flatpak Applications**
- **Desktop Integration**: `io.github.shiftey.Desktop`
- **System Tools**: `it.mijorus.gearlever`, `dev.edfloreshz.CosmicTweaks`
- **Extensions**: `com.mattjakeman.ExtensionManager`

*Note: Gaming Flatpaks (ProtonPlus) are now part of the optional Gaming Mode*

---

## 🔧 System Optimizations

### **Performance Enhancements**
- **ZRAM**: 50% RAM compression with zstd algorithm
- **Pacman Optimization**: Parallel downloads, color output, ILoveCandy
- **Mirror Optimization**: Fastest mirror selection via reflector
- **CPU Microcode**: Automatic Intel/AMD microcode installation
- **Kernel Headers**: Automatic installation for all installed kernels

### **Gaming Mode Features**
- **Interactive Setup**: Y/n prompt with default "Yes" (press Enter to accept)
- **Performance Monitoring**: MangoHud for real-time system monitoring
- **GameMode**: Default GameMode installation (vanilla configuration)
- **Gaming Platforms**: Steam, Lutris, Discord, Heroic Games Launcher
- **Compatibility**: Wine for Windows game compatibility
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

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/gandromidas/archinstaller && cd archinstaller

# Make executable and run
chmod +x install.sh
./install.sh
```

📖 **For detailed instructions and troubleshooting, see [USAGE.md](USAGE.md)**

### **Requirements**
- ✅ Fresh Arch Linux installation
- ✅ Regular user with sudo privileges (NOT root)
- ✅ Internet connection
- ✅ At least 2GB free disk space

### **Installation Process**
1. **System Preparation**: Pacman optimization, mirror updates, microcode installation
2. **Shell Setup**: ZSH, Starship, and shell utilities
3. **Plymouth Setup**: Boot screen configuration
4. **YAY Installation**: AUR helper setup
5. **Programs Installation**: Package installation based on mode and DE
6. **Gaming Mode**: Interactive Y/n prompt for comprehensive gaming setup (optional)
7. **Bootloader and Kernel Configuration**: Detects and configures GRUB or systemd-boot, sets kernel parameters, enables Plymouth, integrates Btrfs support for GRUB, and robustly configures Windows dual-boot if detected
8. **Fail2ban Setup**: Security hardening
9. **System Services**: Service enablement and configuration
10. **Maintenance**: System cleanup and optimization

---

## ⚙️ Configuration Files

### **Fastfetch Configuration** (`configs/config.jsonc`)
- Custom system information display
- Hardware detection and display
- Beautiful terminal output formatting

### **Starship Configuration** (`configs/starship.toml`)
- Nord color scheme integration
- Git status and branch display

### **Package Lists** (`program_lists/`)
- Organized by installation mode and package manager
- Detailed descriptions for each package
- Desktop environment-specific configurations

---

## 🪟 Windows Dual-Boot Automation

- **Detection**: The installer automatically detects if a Windows installation is present (by checking for EFI bootloaders and NTFS partitions).
- **systemd-boot Integration**: 
  - Searches all partitions for the Windows EFI files.
  - Mounts the correct partition and copies the Microsoft EFI files to `/boot/EFI/Microsoft` if needed.
  - Creates a loader entry for Windows if not present.
- **GRUB Integration**: 
  - Installs `os-prober` and enables it in GRUB config.
  - Regenerates the GRUB menu to include Windows.
- **Clock Compatibility**: The hardware clock is set to local time for seamless dual-booting with Windows, preventing time drift issues.
- **NTFS Support**: Installs `ntfs-3g` for NTFS access and to ensure os-prober can detect Windows installations.

---

## 🔍 Advanced Features

### **Error Handling**
- Comprehensive error collection and reporting
- Graceful failure handling
- Detailed error summaries
- Automatic cleanup on success

### **Performance Tracking**
- Installation time tracking
- Package installation statistics
- Progress indicators for long operations
- Memory and resource monitoring

### **VM Detection**
- Automatic virtual machine detection
- VM-specific optimizations
- Guest utilities installation
- Reduced resource usage

### **GPU Detection**
- Automatic NVIDIA/AMD/Intel detection
- Driver-specific optimizations
- Legacy GPU support
- Vulkan and OpenGL configuration

---

## 🛡️ Security Features

### **Network Security**
- **UFW/Firewalld**: Default deny incoming, allow outgoing
- **SSH Protection**: Automatic SSH service configuration
- **KDE Connect**: Port range configuration for mobile integration
- **Fail2ban**: Intelligent intrusion prevention

### **System Security**
- **Service Hardening**: Secure default configurations
- **User Privileges**: Proper sudo configuration
- **Package Verification**: Secure package installation
- **System Updates**: Automatic security updates

---

## 📊 Installation Statistics

### **Default Mode**
- **Pacman Packages**: 30+ packages
- **AUR Packages**: 8+ packages  
- **Flatpak Apps**: 3-4 apps (DE-dependent)
- **System Services**: 9+ services
- **Configuration Files**: 3+ files

### **Minimal Mode**
- **Pacman Packages**: 28 packages
- **AUR Packages**: 4 packages
- **Flatpak Apps**: 1-2 apps (DE-dependent)
- **System Services**: 6+ services
- **Configuration Files**: 2+ files

---

## 🔧 Customization

### **Package Customization**
- Edit package lists in `program_lists/` directory
- Add/remove packages for each installation mode
- Modify desktop environment-specific packages
- Customize Flatpak application selections

### **Configuration Customization**
- Modify `configs/config.jsonc` for Fastfetch
- Edit `configs/starship.toml` for shell prompt
- Customize GameMode configuration
- Adjust Fail2ban settings

### **Script Customization**
- Modify individual scripts in `scripts/` directory
- Add new installation steps
- Customize error handling
- Extend desktop environment support

---

## 🐛 Troubleshooting

### **Common Issues**
- **Permission Errors**: Ensure you're not running as root
- **Network Issues**: Check internet connection and mirrors
- **Package Failures**: Check package availability and dependencies
- **Service Errors**: Verify systemd compatibility

### **Error Recovery**
- Check terminal output for specific error messages
- Review error summary at end of installation
- Re-run specific scripts if needed
- Check system logs for additional information

### **Support**
- Check the [Issues](https://github.com/GAndromidas/archinstaller/issues) page
- Review installation logs
- Verify system requirements
- Test with minimal mode first

---

## 🤝 Contributing

We welcome contributions! Please:

1. **Fork** the repository
2. **Create** a feature branch
3. **Make** your changes with proper error handling
4. **Test** thoroughly on a fresh Arch installation
5. **Submit** a pull request with detailed description

### **Development Guidelines**
- Follow existing code style and structure
- Add comprehensive error handling
- Include progress indicators for long operations
- Test on multiple desktop environments
- Update documentation for new features

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Arch Linux Community**: For the excellent documentation and packages
- **AUR Maintainers**: For maintaining the packages used in this script
- **Desktop Environment Teams**: For KDE, GNOME, and Cosmic
- **Open Source Contributors**: For the tools and utilities that make this possible

---

## 📈 Version History

### **Latest Features**
- ✨ **Optional Gaming Mode**: Interactive Y/n prompt for comprehensive gaming setup
- 🔧 **Streamlined Package Management**: Combined pacman packages, auto-selection in custom mode
- 🎮 **Modern Gaming Support**: Steam, Lutris, Discord, Heroic Games Launcher, ProtonPlus
- 🔒 Improved security with Fail2ban and firewall configuration
- 🖥️ Better desktop environment detection and optimization
- ⚡ Performance improvements with ZRAM and system tuning
- 🎨 Beautiful terminal interface with progress tracking

---

*Transform your Arch Linux installation into a powerful, optimized, and beautiful system with Archinstaller! 🚀*
