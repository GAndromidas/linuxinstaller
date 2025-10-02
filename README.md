# Archinstaller

Comprehensive post-installation automation script for Arch Linux systems with intelligent hardware detection and adaptive configuration.

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

---

## Demo

![archinstaller](https://github.com/user-attachments/assets/7a2d86b9-5869-4113-818e-50b3039d6685)

---

## Overview

Archinstaller transforms a fresh Arch Linux installation into a fully configured, optimized system through comprehensive intelligent hardware and software detection. The installer automatically adapts to your specific hardware configuration, network conditions, and system environment to provide optimal performance and compatibility.

**Core Philosophy: Minimal but Functional**
- Essential packages only
- VLC with plugins for all media playback
- Hardware-adaptive configurations with 12+ intelligent detection systems
- Smart feature detection and optimization
- Optional components (gaming, gestures, snapshots)

**Intelligent Detection Systems**
1. **CPU Detection**: Vendor (Intel/AMD) and generation-specific optimizations
2. **Display Server**: Wayland vs X11 with appropriate packages
3. **Storage Type**: NVMe/SSD/HDD with optimal I/O schedulers
4. **Memory Size**: Adaptive swappiness based on RAM (1GB-32GB+)
5. **Network Speed**: Download optimization based on connection speed
6. **Filesystem**: Btrfs/ext4/XFS/F2FS with specific optimizations
7. **Audio System**: PipeWire vs PulseAudio detection
8. **Hybrid Graphics**: Multi-GPU detection (NVIDIA Optimus)
9. **Kernel Type**: Standard/LTS/Zen/Hardened detection
10. **VM Hypervisor**: KVM/VMware/VirtualBox/Hyper-V specific tools
11. **Desktop Environment**: Version detection (GNOME 45+, Plasma 5/6)
12. **Battery Status**: Low battery warnings during installation
13. **Bluetooth Hardware**: Install only if hardware present
14. **Laptop Detection**: Automatic power management and touchpad optimization
15. **GPU Drivers**: AMD/Intel/NVIDIA with generation detection
16. **Touchpad Hardware**: PS/2 vs I2C with capability assessment

---

## Installation Modes

### Standard Mode
Complete system setup with all recommended packages and tools. Includes productivity applications, system utilities, and desktop environment integration. Suitable for users who want a ready-to-use system.

### Minimal Mode
Essential tools and core functionality only. VLC handles all media playback. Optimized for users who prefer a lightweight installation or plan to customize their system manually.

### Custom Mode
Interactive package selection through a graphical interface. Provides granular control over installed components with detailed package descriptions. For advanced users who want precise control.

---

## Desktop Environment Support

Automatic detection and optimization for:

**KDE Plasma**
- KDE-specific utilities (KDE Connect, Spectacle, Okular, QBittorrent, Kvantum)
- Custom global shortcuts (Meta+Q close window, Meta+Return terminal)
- Removes conflicting packages
- Flatpak integration tools

**GNOME**
- GNOME utilities (Tweaks, Extension Manager, Seahorse, dconf-editor)
- Removes default bloatware (Epiphany, Contacts, Maps, Music, Tour)
- Schema-validated settings (dark theme, window buttons, tap-to-click)
- Custom shortcuts (Meta+Q close window, Meta+Return terminal, PrintScreen, Ctrl+Alt+Delete)
- Compatible with GNOME 40 through 49+

**Cosmic**
- Cosmic-specific utilities and tweaks
- Power management optimization
- Basic desktop configuration

**Generic Support**
- Works with any desktop environment or window manager
- Universal optimizations without DE-specific dependencies

---

## Intelligent Detection Systems

### 1. CPU Detection & Optimization

**Intel CPUs**
- **Modern (6th gen+)**: Intel P-State driver, hardware P-States (HWP), dynamic boost
- **Atom/Celeron/Pentium**: Optimized governors, limited boost configuration
- **Laptop-specific**: thermald thermal management, Intel GPU power optimization
- **Power profiles**: power-profiles-daemon for 6th gen+, tuned-ppd for older/Atom

**AMD CPUs**
- **Ryzen 5000+**: AMD P-State driver, schedutil governor, modern power profiles
- **Ryzen 1000-4000** (2500U, 2600, 3600): ACPI CPUfreq with optimized settings
- **Laptop-specific**: Radeon GPU power management (Vega iGPU optimization)
- **Power profiles**: power-profiles-daemon for 5000+, tuned-ppd for 1000-4000

### 2. Display Server Detection

**Wayland**
- wl-clipboard for clipboard management
- grim + slurp for screenshots
- xdg-desktop-portal-wlr for desktop integration

**X11**
- xclip for clipboard operations
- xorg-xrandr for display configuration
- Traditional X11 tools

### 3. Storage Type Detection

**Automatic I/O Scheduler Optimization**
- **NVMe SSD**: none (multi-queue, best for NVMe)
- **SATA SSD**: mq-deadline (optimized for SSDs)
- **HDD**: bfq (best for rotational drives)
- Persistent udev rules created

### 4. Memory Size Adaptation

**RAM-Based Optimizations**
- **< 4GB**: Swappiness 60 (aggressive swap), reduced cache pressure
- **4-8GB**: Swappiness 30 (moderate swap usage)
- **8-16GB**: Swappiness 10 (minimal swap usage)
- **16GB+**: Swappiness 1 (almost no swap)
- **32GB+**: Option to disable swap entirely

### 5. Network Speed Detection

**Adaptive Download Configuration**
- Tests connection speed with speedtest-cli
- **< 5 Mbit/s**: 3 parallel downloads, warns about slow connection
- **5-25 Mbit/s**: 10 parallel downloads (standard)
- **25-100 Mbit/s**: 10 parallel downloads
- **100+ Mbit/s**: 15 parallel downloads (faster installation)

### 6. Filesystem Detection

**Type-Specific Optimizations**
- **Btrfs**: Snapshot support, compression available
- **ext4**: Reduced reserved blocks to 1% (from 5%)
- **XFS**: Acknowledged as optimized by default
- **F2FS**: Recognized as flash-optimized
- **LUKS**: Encryption detected, TRIM support noted

### 7. Audio System Detection

**Automatic Configuration**
- **PipeWire**: Installs pipewire-alsa, pipewire-jack, pipewire-pulse
- **PulseAudio**: Installs pulseaudio-bluetooth if Bluetooth present
- Detects active audio system automatically

### 8. Hybrid Graphics Detection

**Multi-GPU Systems**
- Detects NVIDIA + Intel/AMD combinations
- Warns about NVIDIA Optimus/hybrid graphics
- Suggests optimus-manager or nvidia-prime
- Provides manual configuration guidance

### 9. Kernel Type Detection

**Kernel-Specific Recognition**
- **linux-lts**: Long-term support kernel (stability focused)
- **linux-zen**: Performance kernel (low latency, gaming)
- **linux-hardened**: Security-focused kernel
- **linux**: Standard balanced kernel

### 10. VM Hypervisor Detection

**Hypervisor-Specific Tools**
- **KVM/QEMU**: qemu-guest-agent (already installed)
- **VMware**: open-vm-tools with vmtoolsd service
- **VirtualBox**: virtualbox-guest-utils with vboxservice
- **Hyper-V**: hyperv utilities
- Automatic installation and service enablement

### 11. Desktop Environment Version

**Version Detection**
- **GNOME**: Detects version number (45, 46, 47+)
- **KDE Plasma**: Detects 5.x vs 6.x (Qt5 vs Qt6)
- **Cosmic**: Recognizes alpha/beta status
- Future-proofs configurations

### 12. Battery Status Check

**Installation Safety**
- Checks battery level before installation
- Warns if battery < 30% on discharge
- Prompts to connect AC adapter
- Prevents installation interruption from power loss

### 13. Bluetooth Hardware Detection

**Smart Package Management**
- Detects Bluetooth hardware presence (USB/PCI/class)
- Only enables service if hardware present
- Installs packages but won't start unused services
- Saves resources on systems without Bluetooth

### 14. Laptop Detection & Optimization

**Automatic Detection Methods**
- Battery presence check (/sys/class/power_supply/BAT*)
- DMI chassis type detection (dmidecode)
- Multiple fallback mechanisms

**Laptop Features** (When Detected)
- TLP power management with CPU-specific tuning
- Touchpad hardware capability detection (PS/2 vs I2C, multi-touch support)
- Tap-to-click, natural scrolling, disable-while-typing
- Optional touchpad gestures (with hardware compatibility warnings)
- Battery status monitoring
- Power profile management (tuned-ppd or power-profiles-daemon based on CPU)
- Intel thermald for thermal management (Intel only)
- GPU power optimization (Intel/AMD specific)

**Intel Laptop Additions**
- thermald for thermal management
- Intel P-State configuration
- Intel GPU power optimization

**AMD Laptop Additions**
- AMD P-State or ACPI CPUfreq configuration
- Radeon DPM (Dynamic Power Management)
- Vega iGPU power profiles

### 15. Touchpad Intelligence

**Hardware Detection**
- Checks xinput device presence
- Verifies multi-touch capability (touch point count)
- Detects libinput driver support
- Identifies PS/2 vs I2C touchpads

**Adaptive Configuration**
- Modern I2C touchpads: Full 3-finger gesture support
- PS/2 touchpads (budget laptops): Warns about limitations, suggests 2-finger gestures
- Missing touchpads: Skips gesture installation
- Provides troubleshooting steps for limited hardware

**Universal Features** (All Touchpads)
- Tap-to-click enabled
- Natural scrolling
- Two-finger scrolling
- Disable-while-typing
- Click-finger method

### 16. GPU Driver Intelligence

**Automatic Detection & Installation**
- AMD: Mesa, AMDGPU, Vulkan with 32-bit libraries
- Intel: Mesa, Intel Vulkan, hardware acceleration
- NVIDIA: Generation detection (Turing+, Maxwell/Pascal, Kepler, Fermi, Tesla)
- VM Detection: Guest utilities (qemu-guest-agent, spice-vdagent)

**Driver Verification**
- Uses lspci -k to verify loaded driver
- Checks Vulkan support availability
- Displays current driver status
- Provides post-reboot verification instructions

---

## System Optimizations

### Performance
- Pacman parallel downloads and optimization (10 concurrent, color output)
- Intelligent ZRAM configuration based on system RAM (dynamic sizing with zstd)
- Automatic traditional swap detection and disable option
- CPU microcode installation (Intel/AMD auto-detected)
- Kernel headers for all installed kernels
- SSD optimization with automatic fstrim
- Mirror list optimization using rate-mirrors

### Security
- Fail2ban for SSH protection (3 attempts, 30-minute ban)
- Firewall configuration (UFW or Firewalld auto-detected)
- Automatic port configuration for installed services (SSH, KDE Connect)
- System service hardening
- Service verification after enabling

### Boot Configuration
- Plymouth boot screen installation and configuration
- Bootloader detection and optimization (GRUB/systemd-boot)
- Windows dual-boot detection and configuration
- Quiet boot parameters with reduced timeout
- NTFS support for Windows partitions
- Automatic EFI file management

### Btrfs Snapshot System
- Automatic Btrfs filesystem detection
- Snapper integration with timeline snapshots
- Pre/post package operation snapshots (snap-pac)
- Bootloader integration for snapshot booting (GRUB: grub-btrfs with grub-btrfsd)
- LTS kernel fallback for system recovery
- GUI management through btrfs-assistant
- Configurable retention policy (5 hourly, 7 daily snapshots)
- Replaces Timeshift with more robust solution

### Power Management
- **Dynamic daemon selection**: tuned-ppd for older CPUs, power-profiles-daemon for modern CPUs
- TLP with CPU-generation-specific configuration
- Intel thermald for thermal management (Intel laptops)
- ZRAM with automatic swap management
- Battery threshold configuration where supported

---

## Package Management

### Core System Tools
System utilities (btop, hwinfo, inxi, ncdu), network tools (net-tools, nmap, speedtest-cli, sshfs), browsers (Firefox, Chromium), file utilities, fonts (Noto, Hack Nerd, Liberation), and essential system packages.

### Media Playback
- VLC media player with all plugins
- Handles all audio/video formats internally
- No redundant system-wide codec packages
- DVD playback support
- Hardware acceleration

### Helper Utilities
Base development tools (base-devel, git), shell enhancements (ZSH, starship, zoxide), system services, package managers (yay for AUR), and essential utilities installed during system preparation.

### Essential Applications
**Standard Mode**: FileZilla, GIMP, KDENlive, OpenRGB, VLC
**Minimal Mode**: VLC only

### AUR Packages
**Standard Mode**: Dropbox, OnlyOffice, rate-mirrors, RustDesk, Spotify, Stremio, Ventoy, VIA
**Minimal Mode**: OnlyOffice, rate-mirrors, RustDesk, Stremio

### Gaming Mode (Optional)
Discord, Steam, Lutris, MangoHud, OBS Studio, Wine, Heroic Games Launcher, GameMode, and performance optimization tools.

---

## Shell Configuration

- ZSH as default shell with Oh-My-Zsh framework
- Starship prompt with git integration and system information
- Zoxide for smart directory navigation (replaces cd)
- Fastfetch system information display with custom configuration
- 50+ organized aliases by category:
  - System maintenance (update, clean, sync, mirror)
  - File operations (with safety flags)
  - Navigation (multiple directory levels)
  - Networking (ip, ports, speed tests)
  - System monitoring (CPU, memory, processes)
  - Archive operations (universal extract function)
  - Package management helpers
- SSH connection aliases template for quick remote access
- Utility functions (extract, mkcd, killp)
- FZF fuzzy finding (Ctrl+R history, Ctrl+T files, Alt+C directories)
- Syntax highlighting and autosuggestions

---

## Error Handling & Recovery

### State Tracking
- Installation state saved to ~/.archinstaller.state
- Automatic step completion tracking
- Resume from last successful step on re-run
- Skip completed steps automatically
- State file removed on successful completion

### Installation Logging
- Complete log saved to ~/.archinstaller.log
- Timestamped entries for all operations
- Persists after installer cleanup
- Includes success, warning, and error messages
- Useful for troubleshooting and review

### Error Management
- Non-critical errors don't halt installation
- Comprehensive error collection and reporting
- Failed package tracking
- Detailed summary at completion
- Installer directory preserved on failure

### Service Verification
- Services verified after enabling
- Active status checked for all services
- Failed services clearly reported
- Distinguishes between enabled-but-not-running vs failed

---

## Architecture

### Modular Design
```
install.sh                    Main orchestration with state tracking
scripts/common.sh             Shared functions and utilities
scripts/system_preparation.sh System updates and core packages
scripts/shell_setup.sh        ZSH, GNOME configs, fastfetch
scripts/plymouth.sh           Boot screen setup
scripts/yay.sh               AUR helper installation
scripts/programs.sh          Application installation with DE detection
scripts/gaming_mode.sh       Gaming tools and optimizations
scripts/bootloader_config.sh Bootloader detection and configuration
scripts/fail2ban.sh          SSH security hardening
scripts/system_services.sh   Services, GPU drivers, laptop optimizations
scripts/maintenance.sh       Cleanup, optimization, Btrfs snapshots
```

### Configuration Files
```
configs/programs.yaml       Package definitions and descriptions
configs/.zshrc             Enhanced ZSH configuration with 50+ aliases
configs/starship.toml      Prompt configuration
configs/MangoHud.conf      Gaming overlay settings
configs/config.jsonc       Fastfetch system information display
configs/kglobalshortcutsrc KDE global shortcuts (Meta+Q, Meta+Return)
```

### Code Quality
- Consistent error handling (set -euo pipefail)
- Function documentation with parameters and return values
- Consolidated package installer (generic function for pacman/AUR/flatpak)
- Variable validation (required parameters)
- Logging to both console and file
- Schema validation for GNOME settings

---

## Installation

### Prerequisites
- Fresh Arch Linux installation
- Active internet connection
- Regular user account with sudo privileges
- Minimum 2GB free disk space

### Quick Start
```bash
git clone https://github.com/gandromidas/archinstaller && cd archinstaller
chmod +x install.sh
./install.sh
```

### Installation Process
1. System requirements validation (OS, internet, disk space, privileges)
2. Installation mode selection (Standard/Minimal/Custom)
3. Automated package installation (10-20 minutes)
4. Optional gaming mode setup
5. Bootloader and security configuration
6. Hardware-specific optimizations (CPU, GPU, laptop)
7. Btrfs snapshot setup (if applicable)
8. System cleanup and optimization
9. Reboot prompt

### Command-Line Options
```bash
./install.sh              # Interactive installation
./install.sh --verbose    # Show detailed package installation
./install.sh --quiet      # Minimal output
./install.sh --help       # Show usage information
```

### Re-Running on Existing Installations

**Safe to re-run!** The installer uses state tracking and non-destructive checks:

**State Tracking**
- Already completed steps are automatically skipped
- State saved to `~/.archinstaller.state`
- Only new features and updates are applied

**What Happens on Re-Run**
- Steps 1-8: Skipped (if already completed)
- Step 9: **Runs new detection systems** (CPU-specific configs, power profiles, I/O schedulers)
- Step 10: Runs maintenance and optimizations
- Configs: Backed up before overwriting (timestamped)

**Force Fresh Installation**
```bash
rm ~/.archinstaller.state
./install.sh
```

**Check Installation Log**
```bash
cat ~/.archinstaller.log  # Review what happened
cat ~/.archinstaller.state # See completed steps
```

---

## Customization

### Adding Packages
Edit `configs/programs.yaml`:
```yaml
essential:
  default:
    - name: "package-name"
      description: "Package description"
```

### Modifying Behavior
Each installation phase is isolated in `scripts/` directory. Modify individual scripts to customize behavior without affecting other components.

### Desktop Environment Extensions
Add desktop environment support by extending `programs.yaml` and updating detection logic in `programs.sh`.

---

## Important Notes

- Execute as regular user, not root (script validates and exits if run as root)
- Designed for fresh Arch Linux installations
- Internet connection required throughout installation
- Reboot recommended after completion for all changes to take effect
- Existing configurations backed up before overwriting (timestamped backups)
- Installation log preserved at ~/.archinstaller.log
- Use --help flag for complete usage information
- State tracking allows resuming failed installations from last successful step
- Installer directory removed on successful completion

---

### Recent Major Updates

### 16 Intelligent Detection Systems (Latest)
1. **CPU Detection**: Intel/AMD with generation-specific optimizations (Intel 6th gen+, AMD Ryzen 1000-5000+)
2. **Display Server**: Wayland vs X11 with appropriate packages (wl-clipboard vs xclip)
3. **Storage Type**: NVMe/SSD/HDD with optimal I/O schedulers (none/mq-deadline/bfq)
4. **Memory Size**: RAM-based swappiness (≤4GB: 60, 8GB: 10, 32GB+: 1)
5. **Network Speed**: Connection-based parallel downloads (3-15 parallel based on Mbit/s)
6. **Filesystem**: Btrfs/ext4/XFS/F2FS optimization, LUKS encryption detection
7. **Audio System**: PipeWire vs PulseAudio automatic configuration
8. **Hybrid Graphics**: Multi-GPU detection with NVIDIA Optimus warnings
9. **Kernel Type**: LTS/Zen/Hardened detection and identification
10. **VM Hypervisor**: KVM/VMware/VirtualBox/Hyper-V specific guest tools
11. **Desktop Environment**: Version detection (GNOME 45+, Plasma 5/6)
12. **Battery Status**: Low battery warnings during installation (prevents power loss)
13. **Bluetooth Hardware**: Service enabled only if hardware present
14. **Laptop Detection**: Complete power management suite (TLP, power profiles, touchpad)
15. **GPU Drivers**: Generation-specific detection and verification
16. **Touchpad Hardware**: PS/2 vs I2C with multi-touch capability assessment

### Power Management Intelligence
- CPU-specific TLP configuration (Intel P-State, AMD P-State, or ACPI fallback)
- Intel thermald for thermal management on Intel laptops
- AMD Radeon GPU power management for Vega iGPU
- **Dynamic power profile daemon**: tuned-ppd for older CPUs (Atom, Ryzen 1000-4000), power-profiles-daemon for modern (Ryzen 5000+, Intel 6th gen+)
- Traditional swap detection and management with ZRAM
- Memory-based swappiness adjustment (1GB-32GB+ adaptive)
- **Hibernation detection**: Preserves disk swap if hibernation configured

### System Optimizations
- **I/O scheduler optimization**: none for NVMe, mq-deadline for SSD, bfq for HDD (persistent udev rules)
- **Network speed-based downloads**: 3-15 parallel based on connection speed test
- **Filesystem-specific tuning**: ext4 reserved blocks reduced to 1%, Btrfs snapshot support, LUKS detection
- **Audio system compatibility**: PipeWire or PulseAudio packages based on detection
- **VM hypervisor guest tools**: Automatic installation for VMware, VirtualBox, Hyper-V
- **ZRAM intelligence**: Automatic for ≤4GB, optional for 4-32GB, skipped/removed for 32GB+

### Enhanced Features
- **Btrfs snapshots** with Snapper (replaces Timeshift completely)
- **GNOME optimizations** with schema validation (GNOME 40-49+ compatible)
- **Enhanced shell** with 50+ organized aliases and SSH connection templates
- **Error recovery** with state tracking (resume from last successful step)
- **Installation logging** to ~/.archinstaller.log (persists after cleanup)
- **Service verification** after enabling (checks active status)
- **GPU driver verification** with lspci -k check
- **Flatpak runtime cleanup** (removes old unused runtimes)
- **Battery check** prevents installation on low battery (<30%)
- **Hibernation awareness** (preserves disk swap if hibernation configured)
- **ZRAM intelligence** (automatic removal on 32GB+, hibernation conflict detection)
- **Display server packages** (Wayland: wl-clipboard/grim/slurp, X11: xclip/xrandr)

### Code Improvements
- Consistent error handling across all scripts (set -euo pipefail)
- Function documentation with parameters and return values
- Consolidated package installer (generic function for all package managers)
- Variable validation for required parameters
- 16 detection functions for adaptive configuration
- Comprehensive hardware and software environment detection

---

## Contributing

Contributions are welcome. To extend functionality:

1. Package additions: Update `configs/programs.yaml`
2. New features: Add modular scripts to `scripts/`
3. Desktop environments: Extend detection and package selection
4. Hardware detection: Add to appropriate detection functions in `system_services.sh` or `system_preparation.sh`

## Frequently Asked Questions

### Can I run this on an existing installation?
**Yes!** The installer safely re-runs on existing installations. It uses state tracking to skip completed steps and only applies new features and updates. Your configs are backed up before being replaced.

### Will this work on my laptop?
**Yes!** The installer automatically detects laptops and applies appropriate optimizations (TLP, touchpad, power management, battery monitoring).

### What about my Ryzen 2500U/2600?
**Fully supported!** These 1st-3rd gen Ryzen CPUs get tuned-ppd (not power-profiles-daemon), AMD-specific TLP config, and Radeon GPU power management.

### Does it support hibernation?
**Yes!** The installer detects hibernation configuration and preserves disk swap when needed. ZRAM conflicts with hibernation are automatically handled.

### What if I have 32GB+ RAM?
**Optimized!** ZRAM is automatically skipped (not needed) or removed if already configured. Swappiness is set to 1 (minimal).

### Will it work with my Intel Atom laptop?
**Yes!** Atom CPUs get tuned-ppd, optimized power management, and PS/2 touchpad detection with appropriate warnings.

---

## License

Licensed under the terms specified in the LICENSE file.

---

**Intelligent Arch Linux system configuration and optimization.**