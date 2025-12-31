<div align="center">

<img width="725" height="163" alt="Screenshot_20251228_155836" src="https://github.com/user-attachments/assets/adb433bd-ebab-4c51-a72d-6208164e1026" />

**LinuxInstaller** is a comprehensive, cross-distribution post-installation automation script that transforms a fresh Linux installation into a fully configured, optimized system. It supports Arch Linux, Fedora, Debian, and Ubuntu with intelligent hardware detection and customizable installation modes.

</div>

## Features

- Package lists are now centralized in per-distro modules and exposed via a simple API
- Improved bootstrapping and safe fallbacks for UI and tooling
- Cleaner UX with graceful fallbacks when gum is not available
- Optional final cleanup step to remove temporary helper tools
- Distribution module fixes and standardization
- Enhanced safety and observability with improved dry-run behavior, idempotent state tracking with resume capability, and centralized logging to ~/.linuxinstaller.log
- Wake-on-LAN integration to automatically detect wired NICs and configure Wake-on-LAN
- Flatpak package installations now present live, user-visible progress

## Universal Distribution Support

### Arch Linux
- Full AUR integration
- Pacman optimization
- Plymouth boot screen

### Fedora
- RPM Fusion repositories
- DNF optimization
- firewalld configuration

### Debian/Ubuntu
- APT optimization
- Universe/Multiverse repositories
- UFW firewall

## Desktop Environment Integration

### KDE Plasma
- Global shortcuts, theme configuration, KDE Connect setup

### GNOME
- Extensions, theme optimization, workspace configuration

### Universal
- Shell setup with ZSH, syntax highlighting, Starship prompt

## Gaming Environment
- Steam, Faugus (Flatpak), and Wine installation
- Vulkan drivers and graphics optimization
- MangoHud performance monitoring
- GameMode system optimization

## Security Hardening
- Fail2ban with enhanced security settings
- Firewall configuration (UFW/firewalld)
- AppArmor/SELinux integration
- SSH security hardening

## Performance Optimization
- ZRAM configuration with systemd-zram-generator
- CPU governor optimization
- Swappiness tuning
- Network performance optimization

## Smart Hardware Detection

### Logitech Hardware
- Automatic solaar installation for mouse/keyboard management
- USB, Bluetooth, HID detection
- Automatic installation when Logitech hardware is found

### GPU Detection
- Automatic graphics driver installation based on detected hardware
- NVIDIA: Installs appropriate NVIDIA drivers and Vulkan support
- AMD: Configures AMDGPU drivers and Vulkan libraries
- Intel: Sets up Intel graphics with Vulkan support
- Virtual Machines: Installs VM-specific drivers

### Bootloader Detection
- GRUB and systemd-boot support

### Filesystem Detection
- Btrfs snapshot setup with Snapper

## Requirements

- Fresh Linux installation (Arch, Fedora, Debian, or Ubuntu)
- Active internet connection
- Regular user account with sudo privileges
- Minimum 2GB free disk space

## Quick Start

```bash
wget https://github.com/GAndromidas/linuxinstaller/raw/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## Installation Modes

### Standard Mode
Complete setup with all recommended packages for a full desktop experience.

### Minimal Mode
Essential tools only for lightweight installations and minimal resource usage.

### Server Mode
Headless server configuration with essential services and security hardening.

Note: Interactive Gaming Prompt

When you choose Standard or Minimal mode the installer will prompt whether you like to install the Gaming package suite (Steam, Faugus (Flatpak), Wine, etc.). If gum is available the confirmation dialog defaults to Yes; in text mode you will be prompted with [Y/n], defaulting to Yes. Server mode is headless and will not prompt for gaming packages.

## Package Management

Package lists are now defined in per-distro modules (e.g., scripts/arch_config.sh, scripts/fedora_config.sh, scripts/debian_config.sh) and are exposed via the distro_get_packages <section> <type> API.

Example:

ARCH_NATIVE_STANDARD=(
  git
  curl
  vim
)

ARCH_AUR_STANDARD=(
  onlyoffice-bin
  rustdesk-bin
)

Arch-specific installation behavior:

Standard mode (when Arch is detected and you select Standard):
- The installer will install:
  - ARCH_NATIVE_STANDARD and ARCH_NATIVE_STANDARD_ESSENTIALS
  - ARCH_AUR_STANDARD
  - ARCH_FLATPAK_STANDARD
  - The desktop-environment specific group for your DE (e.g. ARCH_DE_KDE_NATIVE or ARCH_DE_GNOME_NATIVE)
- This ensures the full standard desktop experience and the extra standard essentials are included.

Minimal mode:
- The installer will still include the full native base ARCH_NATIVE_STANDARD (so base tooling is always present), plus the ARCH_NATIVE_MINIMAL set (and ARCH_AUR_MINIMAL / ARCH_FLATPAK_MINIMAL where applicable).

Server mode:
- The installer will include ARCH_NATIVE_STANDARD together with the server-specific native set (ARCH_NATIVE_SERVER).
- Desktop-environment specific packages are skipped in server mode (headless setup).

This policy ensures the consistent presence of base tooling across modes while keeping minimal and server profiles lean in other respects.

## Distribution-Specific Configs

Each distribution has its own configuration directory with optimized settings.

- Shell Configuration: Distro-specific .zshrc files with optimized aliases and functions
- Prompt Configuration: Starship prompt with distribution-appropriate icons
- System Information: Fastfetch configuration with OS-specific branding

## Supported Features by Distribution

| Feature | Arch Linux | Fedora | Debian | Ubuntu |
|---------|------------|--------|--------|---------|
| AUR Support | Yes | No | No | No |
| RPM Fusion | No | Yes | No | No |
| Universe Repos | No | No | Yes | Yes |
| Plymouth Boot | Yes | Yes | Yes | Yes |
| Snap Support | No | No | No | Yes |
| Flatpak Support | Yes | Yes | Yes | Yes |

## Hardware Detection

### Logitech Hardware
The installer automatically detects Logitech hardware and installs solaar for enhanced device management.

- USB Detection: Scans for Logitech USB devices
- Bluetooth Detection: Identifies Logitech Bluetooth devices
- HID Detection: Finds Logitech Human Interface Devices
- Automatic Installation: Installs solaar when Logitech hardware is found

### GPU Detection
Automatic graphics driver installation based on detected hardware.

- NVIDIA: Installs appropriate NVIDIA drivers and Vulkan support
- AMD: Configures AMDGPU drivers and Vulkan libraries
- Intel: Sets up Intel graphics with Vulkan support
- Virtual Machines: Installs VM-specific drivers (VMware, VirtualBox, Hyper-V)

## Security Features

### Fail2ban Configuration
Enhanced security settings (1-hour ban, 3 failed attempts).
- SSH brute-force protection.
- systemd backend for better integration.

### Firewall Management
- Arch/Fedora: firewalld with optimized rules
- Debian/Ubuntu: UFW with SSH rate limiting
- Automatic service enablement and configuration

### User Group Management
Automatic addition to essential groups:
- wheel/sudo for administrative privileges
- input, video, storage for hardware access
- docker if Docker is installed

## Performance Features

### ZRAM Configuration
- Automatic ZRAM setup with systemd-zram-generator
- Memory-based swap with compression
- Optimized for systems with limited RAM

### CPU Optimization
- Performance governor configuration
- CPU frequency scaling optimization
- Power management tuning

### Filesystem Optimization
- Btrfs snapshot setup with Snapper
- TRIM scheduling for SSDs
- Mount option optimization

## Gaming Features

### Environment Setup
- Steam and Faugus (Flatpak) installation
- Wine configuration and setup

### Performance Monitoring
- MangoHud overlay installation and configuration
- Real-time system monitoring
- Game-specific performance optimization

### Graphics Optimization
- Vulkan driver installation
- GPU-specific configuration
- Anti-aliasing and rendering optimization

## Maintenance Features

### Automated Updates
- Distribution-specific automatic update configuration
- Security update prioritization
- Package cleanup automation

### System Monitoring
- Health check automation
- Log rotation configuration
- Performance monitoring setup

### Backup Solutions
- Automated backup script creation
- Important directory backup configuration
- Backup schedule setup

## Installation Progress

The installer provides detailed progress tracking.

## Resume Capability

The installer supports resuming interrupted installations.

## Troubleshooting

### Gum Installation Fails

```bash
sudo pacman -S gum  # Arch
sudo dnf install gum  # Fedora
sudo apt install gum  # Debian/Ubuntu
```

### Permission Issues

```bash
chmod +x install.sh
sudo ./install.sh
```

### Log Files

Installation logs are saved to ~/.linuxinstaller.log for troubleshooting.

## Contributing

We welcome contributions! Please see our Contributing Guide for details.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Arch Linux Community: For excellent documentation and package management
- Fedora Project: For RPM Fusion and excellent package ecosystem
- Debian/Ubuntu Teams: For stable and reliable distributions
- All Contributors: For testing, feedback, and improvements

Built with love for the Linux community
