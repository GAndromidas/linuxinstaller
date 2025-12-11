<div align="center">

# Archinstaller

</div>

[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)
[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)


**Archinstaller** is an advanced post-installation script for Arch Linux that automates the transition from a base system to a fully configured, highly optimized, and ready-to-use desktop environment. It leverages intelligent detection systems to tailor the installation to your specific hardware, ensuring optimal performance, security, and stability.

Built with the Arch Linux philosophy of simplicity and minimalism, Archinstaller provides a clean, professional installation experience with enhanced user interface features including real-time progress tracking, time estimation, and intelligent resume functionality.

## Demo
<div align="center">
<img width="666" height="369" alt="archinstaller" src="https://github.com/user-attachments/assets/f00f6518-2f10-42f5-b312-d098b3e0f913" />
</div>

## Core Philosophy

This project is built on the principle of **Intelligent Automation**. Instead of providing a one-size-fits-all setup, Archinstaller inspects your system's hardware and software to make smart decisions, applying best-practice configurations that would otherwise require hours of manual research and tweaking.

## Key Features

### System Intelligence & Automation

*   **Comprehensive Hardware Detection**: Automatically identifies and optimizes for:
    *   CPU vendor (Intel/AMD) with microcode installation
    *   GPU detection (NVIDIA/AMD/Intel/VM guest) with appropriate driver installation
    *   Storage type (NVMe/SSD/HDD) with optimal I/O scheduler configuration
    *   Memory size with adaptive ZRAM and swappiness tuning
    *   Filesystem type (Btrfs/ext4/XFS/F2FS) with filesystem-specific optimizations
    *   Laptop-specific hardware (battery, touchpad, thermal management)
    *   Network adapters with universal Ethernet detection
    *   Audio system (PipeWire/PulseAudio) with automatic configuration
    *   Virtual machine detection with guest utilities
    *   Hybrid graphics detection for Optimus systems

*   **Intelligent Driver Management**: 
    *   Installs correct graphics drivers based on GPU detection
    *   Handles legacy NVIDIA drivers (Kepler, Fermi, Tesla) via AUR
    *   Automatically installs VM guest utilities (QEMU, VMware, VirtualBox, Hyper-V)
    *   Configures Vulkan support for all GPU vendors

*   **Dynamic Performance Optimization**: 
    *   ZRAM swap configuration based on RAM size (disabled for 32GB+ systems)
    *   I/O scheduler optimization (none for NVMe, mq-deadline for SSD, bfq for HDD)
    *   Memory-based swappiness tuning (1-60 based on RAM)
    *   Filesystem optimizations (ext4 reserved blocks, Btrfs snapshots)
    *   Optimized parallel downloads configuration

*   **Desktop Environment Integration**: 
    *   Detects and optimizes for KDE Plasma, GNOME, and Cosmic
    *   Applies desktop-specific keyboard shortcuts and configurations
    *   Installs desktop-appropriate packages automatically

### Security & Hardening

*   **Intelligent Firewall Configuration**:
    *   Auto-detects and configures Firewalld or UFW
    *   Secure defaults (deny incoming, allow outgoing)
    *   Always allows SSH to prevent lockout
    *   Automatically opens KDE Connect ports when KDE Plasma is detected
    *   Verifies firewall is active and rules are properly applied

*   **Boot Security**:
    *   Secures boot partition permissions (700 for Linux filesystems)
    *   Configures ESP mount options (fmask/dmask) for FAT32 partitions
    *   Protects random-seed file with 600 permissions
    *   Works with both GRUB and systemd-boot

*   **Fail2ban Integration**:
    *   Stricter policy for SSH protection
    *   Automatic configuration and service enablement

*   **Network Resilience**:
    *   Automatic network retry logic with exponential backoff
    *   Handles temporary network interruptions gracefully

### Advanced System Features

*   **Btrfs Snapshot System**: 
    *   Full Btrfs snapshot and recovery solution with `snapper`
    *   Bootloader integration with GRUB for easy rollbacks
    *   Automatic snapshot configuration

*   **Wake-on-LAN Support**:
    *   Universal Ethernet adapter detection (works with any interface name)
    *   Automatically enables WoL on all supported Ethernet adapters
    *   Creates persistent systemd services for each adapter
    *   Displays MAC addresses for remote wake commands

*   **Dedicated Server Mode**: 
    *   One-click setup for true headless server environment
    *   Installs curated server tools (Docker, Portainer, etc.)
    *   Skips all graphical components and desktop shells
    *   Applies secure-by-default firewall configuration
    *   Enables only essential services (cronie, sshd, fstrim, paccache)

*   **Optional Gaming Mode**: 
    *   Complete gaming environment setup
    *   Includes Steam, Lutris, Heroic Games Launcher, MangoHud, Goverlay, and GameMode
    *   Performance optimizations for gaming workloads

*   **Power Management**: 
    *   Advanced power-saving features for laptops
    *   Intelligent daemon selection (power-profiles-daemon for modern systems, tuned-ppd for older)
    *   CPU-specific optimizations (Intel thermald, AMD P-State detection)
    *   Touchpad gesture support with libinput-gestures
    *   Battery status monitoring and warnings

### User Experience

*   **Flexible Installation Modes**: 
    *   **Standard**: Feature-rich setup with all recommended packages
    *   **Minimal**: Lightweight installation with essential tools only
    *   **Server**: True headless server environment
    *   **Custom**: Interactive selection of packages to install

*   **Enhanced Shell**: 
    *   Pre-configured high-performance Zsh environment
    *   Starship prompt for modern terminal experience
    *   Syntax highlighting and autocompletion

*   **Smart Resume Functionality**: 
    *   Tracks installation progress with state file
    *   Can be safely re-run to resume from last completed step
    *   Interactive menu showing completed steps
    *   File locking prevents race conditions

*   **Real-time Progress Tracking**: 
    *   Visual progress bars with step counters
    *   Time estimation that improves as installation progresses
    *   Step-by-step status updates

*   **Professional Interface**: 
    *   Clean, minimal design following Arch Linux principles
    *   Enhanced visual feedback with `gum` (with fallback to traditional prompts)
    *   Comprehensive logging to `~/.archinstaller.log`
    *   Automatic cleanup of temporary files

## Installation Steps

The installer performs 10 comprehensive steps:

1.  **System Preparation**: Updates package lists, installs essential utilities, and optimizes download settings
2.  **Shell Setup**: Installs and configures Zsh with Starship prompt
3.  **Plymouth Setup**: Configures graphical boot screen (skipped in server mode)
4.  **Yay Installation**: Installs AUR helper for additional software packages
5.  **Programs Installation**: Installs applications based on desktop environment and installation mode
6.  **Gaming Mode**: Optional setup for gaming tools and optimizations (skipped in server mode)
7.  **Bootloader Configuration**: Configures GRUB or systemd-boot with kernel parameters and security
8.  **Fail2ban Setup**: Configures SSH protection with fail2ban
9.  **System Services**: Comprehensive system configuration including:
    *   Firewall setup (Firewalld or UFW)
    *   User group configuration (wheel, input, video, storage, docker, libvirt, etc.)
    *   Service enablement (bluetooth, cronie, sshd, power-profiles-daemon, etc.)
    *   Hardware detection and optimization
    *   ZRAM swap configuration
    *   Laptop optimizations (if applicable)
    *   Wake-on-LAN configuration
    *   GPU driver installation
    *   Audio system detection
    *   Storage and filesystem optimizations
10. **Maintenance**: Final cleanup, package cache management, and system verification

## Installation

### Prerequisites

*   A fresh, minimal Arch Linux installation with an active internet connection
*   A regular user account with `sudo` privileges
*   Minimum 2GB free disk space

### Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/gandromidas/archinstaller.git
    ```

2.  **Navigate to the directory:**
    ```bash
    cd archinstaller
    ```

3.  **Run the installer:**
    ```bash
    ./install.sh
    ```

The script will present a menu where you can choose your desired installation mode.

### Command-Line Options

```bash
./install.sh [OPTIONS]
```

**Options:**
*   `-h, --help`: Show help message and exit
*   `-v, --verbose`: Enable verbose output (show all package installation details)
*   `-q, --quiet`: Quiet mode (minimal output)
*   `-d, --dry-run`: Preview what will be installed without making changes

### Installation Experience

The installer provides a modern, user-friendly experience with:

*   **Interactive Menu**: Clean interface powered by `gum` for mode selection and confirmations (with fallback to traditional prompts)
*   **Progress Visualization**: Real-time progress bars showing step counters for each step
*   **Time Estimation**: Dynamic time estimates that improve as installation progresses
*   **Resume Support**: If interrupted, the installer can resume from the last completed step
*   **Professional Summary**: Minimal, clean installation summary following Arch Linux principles
*   **Automatic Cleanup**: Removes temporary files and packages after successful installation
*   **Comprehensive Logging**: All operations logged to `~/.archinstaller.log`

## Customization

This installer is designed to be easily customized. The package lists for all installation modes are managed in `configs/programs.yaml`. This file is structured into logical groups (`common`, `desktop_base`, `server`, `gaming`, etc.), allowing you to add or remove packages to perfectly match your preferences without altering the script logic.

### Configuration Files

*   `configs/programs.yaml`: Package lists for all installation modes
*   `configs/gaming_mode.yaml`: Gaming-specific packages and configurations
*   `configs/starship.toml`: Starship prompt configuration
*   `configs/MangoHud.conf`: MangoHud gaming overlay configuration
*   `configs/kglobalshortcutsrc`: KDE keyboard shortcuts

## Hardware Support

### CPU Support
*   Intel: Microcode installation, P-State detection, thermald for laptops
*   AMD: Microcode installation, P-State detection (Ryzen 5000+), ACPI CPUfreq fallback

### GPU Support
*   NVIDIA: Latest drivers, open-dkms for Turing+, legacy drivers via AUR (Kepler/Fermi/Tesla)
*   AMD: Mesa, AMDGPU driver, Vulkan support
*   Intel: Mesa, i915/xe driver, Vulkan support
*   Virtual Machines: QEMU guest agent, Spice, VirtualBox tools, VMware tools, Hyper-V

### Storage Support
*   NVMe: None scheduler (multi-queue)
*   SATA SSD: mq-deadline scheduler
*   HDD: bfq scheduler
*   Filesystems: Btrfs, ext4, XFS, F2FS optimizations

### Network Support
*   Universal Ethernet adapter detection (eth0, enp*, eno*, ens*, etc.)
*   Wake-on-LAN configuration for all supported adapters
*   Optimized pacman configuration with parallel downloads

## Troubleshooting

### Resume Installation

If the installation is interrupted, simply run the installer again:
```bash
./install.sh
```

The installer will automatically detect completed steps and resume from where it left off.

### Fresh Start

To start over completely:
```bash
rm ~/.archinstaller.state
./install.sh
```

### View Logs

Check the installation log for detailed information:
```bash
cat ~/.archinstaller.log
```

### Common Issues

*   **Network errors**: The installer includes automatic retry logic. If issues persist, check your internet connection
*   **Package installation failures**: Check the log file for specific error messages
*   **Permission errors**: Ensure you're running as a regular user with sudo privileges (not as root)

## Contributing

Contributions are welcome! Please feel free to submit a pull request for improvements or open an issue to report a bug or request a new feature.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
