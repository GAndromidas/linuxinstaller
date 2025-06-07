# Archinstaller: Arch Linux Post-Installation Script

[![MIT License](https://img.shields.io/github/license/GAndromidas/archinstaller.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/GAndromidas/archinstaller.svg)](https://github.com/GAndromidas/archinstaller/stargazers)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg)](https://github.com/GAndromidas/archinstaller/commits/main)

---

## 🎬 Demo Video

[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

![archinstaller](https://github.com/user-attachments/assets/72ff3e94-dd8d-4e18-8c13-30f8b6ba4ef6)

---

## 🚀 Overview

**archinstaller** is a comprehensive post-installation script for Arch Linux that automates system configuration, package installation, and desktop environment setup. It provides two installation modes: Default (full-featured) and Minimal (core utilities only), with automatic desktop environment detection and customization.

---

## 📚 Table of Contents

1. [Features](#features)
2. [Quick Start](#quick-start)
3. [Usage Details](#usage-details)
4. [Script Details](#script-details)
5. [FAQ & Troubleshooting](#faq--troubleshooting)
6. [Contributing](#contributing)
7. [License](#license)
8. [Acknowledgments](#acknowledgments)

---

## ✨ Features

### System Configuration
- Enhanced Pacman configuration (color, parallel downloads, ILoveCandy)
- Mirrorlist optimization via reflector
- CPU microcode installation (Intel/AMD)
- Kernel headers installation for all installed kernels
- Locale and timezone setup
- Sudo password feedback configuration
- UFW firewall setup and configuration

### Desktop Environment Support
- Automatic detection of KDE, GNOME, and Cosmic DEs
- DE-specific package installation and removal
- Customized Flatpak application sets for each DE
- Fallback to minimal set for unsupported DEs/WMs

### Package Management
- YAY AUR helper installation
- Flatpak integration with Flathub
- Comprehensive package sets:
  - Default mode: Full suite of applications
  - Minimal mode: Essential utilities only
- Automatic handling of Pacman, AUR, and Flatpak packages

### User Experience
- Color-coded, step-wise installation process
- Progress tracking and error reporting
- Idempotent operations (safe to run multiple times)
- No password reprompting during installation
- Automatic service enablement (Bluetooth, cron, ufw, etc.)

---

## ⚡ Quick Start

```bash
git clone https://github.com/gandromidas/archinstaller && cd archinstaller
chmod +x install.sh
./install.sh
```

Follow the interactive menu to select:
- Default Installation (full-featured setup)
- Minimal Installation (core utilities only)
- Exit

---

## 📒 Usage Details

- Run as a regular user with sudo privileges (not as root)
- The script will guide you through all installation choices
- Installation mode (Default/Minimal) is selected once at the start
- All sub-scripts are modular and use consistent output formatting
- Designed to be idempotent—safe to run multiple times

---

## 🛠️ Script Details

### Structure
- **install.sh**: Main orchestrator script
- **scripts/install_yay.sh**: YAY AUR helper installation
- **scripts/programs.sh**: Package installation and DE customization
- **scripts/fail2ban.sh**: Fail2ban setup (optional)
- **scripts/setup_plymouth.sh**: Plymouth setup (optional)
- **configs/**: Configuration templates

### Package Sets
- **Default Mode**:
  - Full suite of applications
  - DE-specific optimizations
  - Comprehensive AUR packages
  - Extended Flatpak selection
- **Minimal Mode**:
  - Core system utilities
  - Essential applications only
  - Basic AUR packages
  - Minimal Flatpak selection

---

## ❓ FAQ & Troubleshooting

**Q:** Do I need to run this as root?  
**A:** No, run as a regular user with sudo privileges.

**Q:** What if something fails?  
**A:** Check the error output in the terminal. The script provides detailed error reporting.

**Q:** Can I customize what gets installed?  
**A:** Yes, you can edit the package lists in `programs.sh` or choose between Default and Minimal modes.

**Q:** Does it work with my desktop environment?  
**A:** The script automatically detects and optimizes for KDE, GNOME, and Cosmic DEs. Other DEs/WMs will use the minimal package set.

---

## 🤝 Contributing

Contributions are welcome! Please fork this repository and submit a pull request.  
- Follow the existing code style
- Add comments for clarity
- See the [issues](https://github.com/GAndromidas/archinstaller/issues) page for ideas

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by various Arch Linux setup guides and scripts
- Special thanks to the Arch Linux community for their extensive documentation and support

---

> _Enjoy your automated Arch Linux setup!_
