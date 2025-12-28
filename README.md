# LinuxInstaller

<img width="633" height="458" alt="Screenshot_20251226_185613" src="https://github.com/user-attachments/assets/11723b4c-76de-404d-98ac-7e28745302dd" />

**LinuxInstaller** is a comprehensive, cross-distribution post-installation automation script that transforms a fresh Linux installation into a fully configured, optimized system. It supports Arch Linux, Fedora, Debian, and Ubuntu with intelligent hardware detection and customizable installation modes.

## ✨ Features

### 🔧 Notable Improvements
- Robust YAML parsing and package discovery across multiple `programs.yaml` shapes (per-distro, package-manager keyed, and desktop-environment sections), improving reliability across Arch, Fedora, Debian, and Ubuntu.
- Improved bootstrapping and safe fallbacks for UI and tooling: the installer now attempts to install `gum`, `yq`, and `figlet` via the package manager and will fall back to downloading reputable binaries when packages are unavailable; DRY-RUN support provides a safe preview mode.
- Cleaner UX with graceful fallbacks when `gum` isn't available — plain-text output is consistent and readable while styled `gum` output is used when present.
- Optional final cleanup step: the installer can optionally remove temporary helper tools it installed (keeps the user's environment tidy).
- Distribution module fixes and standardization (Arch and Fedora): AUR helper installation and DNF/COPR handling have been standardized and improved for robustness.
- Enhanced safety and observability: improved dry-run behavior, idempotent state tracking with resume capability, and centralized logging to `~/.linuxinstaller.log`.
- Smarter DE and gaming handling: better desktop-environment detection, more flexible flatpak/snap handling, and dedicated gaming/performance tweaks.

### 🎯 **Universal Distribution Support**
- **Arch Linux**: Full AUR integration, Pacman optimization, Plymouth boot screen
- **Fedora**: RPM Fusion repositories, DNF optimization, firewalld configuration  
- **Debian/Ubuntu**: APT optimization, Universe/Multiverse repositories, UFW firewall

### 🖥️ **Desktop Environment Integration**
- **KDE Plasma**: Global shortcuts, theme configuration, KDE Connect setup
- **GNOME**: Extensions, theme optimization, workspace configuration
- **Universal**: Shell setup, ZSH with syntax highlighting, Starship prompt

### 🎮 **Gaming Environment**
- Steam, Lutris, and Wine installation
- Vulkan drivers and graphics optimization
- MangoHud performance monitoring
- GameMode system optimization

### 🔒 **Security Hardening**
- Fail2ban with enhanced security settings
- Firewall configuration (UFW/firewalld)
- AppArmor/SELinux integration
- SSH security hardening

### ⚡ **Performance Optimization**
- ZRAM configuration with systemd-zram-generator
- CPU governor optimization
- Swappiness tuning
- Network performance optimization

### 🔧 **Smart Hardware Detection**
- **Logitech Hardware**: Automatic solaar installation for mouse/keyboard management
- **GPU Detection**: Automatic driver installation (NVIDIA, AMD, Intel)
- **Bootloader Detection**: GRUB and systemd-boot support
- **Filesystem Detection**: Btrfs snapshot setup with Snapper

## 📋 Requirements

- Fresh Linux installation (Arch, Fedora, Debian, or Ubuntu)
- Active internet connection
- Regular user account with sudo privileges
- Minimum 2GB free disk space

## 🚀 Quick Start

```bash
# Download and run the installer
wget https://github.com/GAndromidas/linuxinstaller/raw/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## 🎨 Installation Modes

### Standard Mode
Complete setup with all recommended packages for a full desktop experience.

### Minimal Mode  
Essential tools only for lightweight installations and minimal resource usage.

### Server Mode
Headless server configuration with essential services and security hardening.

### Custom Mode
Interactive selection of packages and features to install.

## 📁 Project Structure

```
linuxinstaller/
├── install.sh                 # Main entry point with enhanced menu system
├── configs/                   # Distribution-specific configuration files
│   ├── programs.yaml          # Package lists for different modes
│   ├── package_map.yaml       # Generic to distro-specific package mappings
│   ├── arch/                  # Arch Linux specific configs
│   │   ├── .zshrc            # ZSH configuration
│   │   ├── starship.toml     # Starship prompt config
│   │   ├── config.jsonc      # Fastfetch system info config
│   │   ├── MangoHud.conf     # MangoHud performance overlay
│   │   └── kglobalshortcutsrc # KDE global shortcuts
│   ├── fedora/               # Fedora specific configs
│   │   ├── .zshrc            # ZSH configuration
│   │   ├── starship.toml     # Starship prompt config
│   │   └── config.jsonc      # Fastfetch system info config
│   └── debian/               # Debian/Ubuntu specific configs
│       ├── .zshrc            # ZSH configuration
│       ├── .zshrc.ubuntu     # Ubuntu-specific ZSH config
│       ├── starship.toml     # Starship prompt config
│       └── config.jsonc      # Fastfetch system info config
└── scripts/                  # Core functionality modules
    ├── arch_config.sh        # Arch Linux configuration
    ├── fedora_config.sh      # Fedora configuration
    ├── debian_config.sh      # Debian/Ubuntu configuration
    ├── kde_config.sh         # KDE desktop configuration
    ├── gnome_config.sh       # GNOME desktop configuration
    ├── gaming_config.sh      # Gaming environment setup
    ├── security_config.sh    # Security hardening
    ├── performance_config.sh # Performance optimization
    └── maintenance_config.sh # System maintenance
```

## 🔧 Configuration

### Package Management
The installer uses YAML-based configuration for package management:

```yaml
# Example from programs.yaml
arch:
  standard:
    native:
      - git
      - curl
      - vim
    aur:
      - onlyoffice-bin
      - rustdesk-bin
```

### Distribution-Specific Configs
Each distribution has its own configuration directory with optimized settings:

- **Shell Configuration**: Distro-specific `.zshrc` files with optimized aliases and functions
- **Prompt Configuration**: Starship prompt with distribution-appropriate icons
- **System Information**: Fastfetch configuration with OS-specific branding

## 🎯 Supported Features by Distribution

| Feature | Arch Linux | Fedora | Debian | Ubuntu |
|---------|------------|--------|--------|---------|
| AUR Support | ✅ | ❌ | ❌ | ❌ |
| RPM Fusion | ❌ | ✅ | ❌ | ❌ |
| Universe Repos | ❌ | ❌ | ✅ | ✅ |
| Plymouth Boot | ✅ | ✅ | ✅ | ✅ |
| Snap Support | ❌ | ❌ | ❌ | ✅ |
| Flatpak Support | ✅ | ✅ | ✅ | ✅ |

## 🔍 Hardware Detection

### Logitech Hardware
The installer automatically detects Logitech hardware and installs solaar for enhanced device management:

- **USB Detection**: Scans for Logitech USB devices
- **Bluetooth Detection**: Identifies Logitech Bluetooth devices  
- **HID Detection**: Finds Logitech Human Interface Devices
- **Automatic Installation**: Installs solaar when Logitech hardware is found

### GPU Detection
Automatic graphics driver installation based on detected hardware:

- **NVIDIA**: Installs appropriate NVIDIA drivers and Vulkan support
- **AMD**: Configures AMDGPU drivers and Vulkan libraries
- **Intel**: Sets up Intel graphics with Vulkan support
- **Virtual Machines**: Installs VM-specific drivers (VMware, VirtualBox, Hyper-V)

## 🛡️ Security Features

### Fail2ban Configuration
- Enhanced security settings (1-hour ban, 3 failed attempts)
- SSH brute-force protection
- systemd backend for better integration

### Firewall Management
- **Arch/Fedora**: firewalld with optimized rules
- **Debian/Ubuntu**: UFW with SSH rate limiting
- Automatic service enablement and configuration

### User Group Management
Automatic addition to essential groups:
- `wheel`/`sudo` for administrative privileges
- `input`, `video`, `storage` for hardware access
- `docker` if Docker is installed

## ⚡ Performance Features

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

## 🎮 Gaming Features

### Environment Setup
- Steam and Lutris installation
- Wine configuration and setup
- Protontricks for Steam compatibility

### Performance Monitoring
- MangoHud overlay installation and configuration
- Real-time system monitoring
- Game-specific performance optimization

### Graphics Optimization
- Vulkan driver installation
- GPU-specific configuration
- Anti-aliasing and rendering optimization

## 🔧 Maintenance Features

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

## 📊 Installation Progress

The installer provides detailed progress tracking:

```
[1/10] Arch Linux Enhanced Configuration
[2/10] Installing Packages (standard)
[3/10] Running Distribution-Specific Configuration
[4/10] Configuring Desktop Environment
[5/10] Configuring Gaming Environment
[6/10] Configuring Security Features
[7/10] Applying Performance Optimizations
[8/10] Setting up Maintenance Tools
[9/10] Finalizing Installation
[10/10] Installation Complete!
```

## 🔄 Resume Capability

The installer supports resuming interrupted installations:

```bash
# Resume from where you left off
sudo ./install.sh

# Clear previous state and start fresh
sudo ./install.sh --fresh
```

## 🐛 Troubleshooting

### Common Issues

**Gum Installation Fails**
```bash
# Manual installation
sudo pacman -S gum  # Arch
sudo dnf install gum  # Fedora
sudo apt install gum  # Debian/Ubuntu
```

**YQ Installation Fails**
```bash
# Manual installation
sudo pacman -S go-yq  # Arch
sudo dnf install yq   # Fedora
sudo apt install yq   # Debian/Ubuntu
```

**Permission Issues**
```bash
# Ensure script is executable
chmod +x install.sh

# Run with sudo
sudo ./install.sh
```

### Log Files
Installation logs are saved to `~/.linuxinstaller.log` for troubleshooting.

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Arch Linux Community**: For excellent documentation and package management
- **Fedora Project**: For RPM Fusion and excellent package ecosystem  
- **Debian/Ubuntu Teams**: For stable and reliable distributions
- **All Contributors**: For testing, feedback, and improvements

## 🔗 Related Projects

- [Archinstaller](https://github.com/archinstaller/archinstaller)
- [Fedorainstaller](https://github.com/fedorainstaller/fedorainstaller)
- [Debianinstaller](https://github.com/debianinstaller/debianinstaller)

---

**Built with ❤️ for the Linux community**
```
</tool_response>
