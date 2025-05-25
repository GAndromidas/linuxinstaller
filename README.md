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

**archinstaller** is a user-friendly and highly customizable post-install script for Arch Linux. It automates essential system configuration, package installation, and desktop setup, allowing you to get started with a polished Arch system in minutes.

---

## 📚 Table of Contents

1. [Features](#features)
2. [Quick Start](#quick-start)
3. [Usage Details](#usage-details)
4. [Script Details](#script-details)
5. [FAQ & Troubleshooting](#faq--troubleshooting)
6. [Contributing](#contributing)
7. [Roadmap](#roadmap)
8. [License](#license)
9. [Acknowledgments](#acknowledgments)

---

## ✨ Features

- Automated installation and configuration of kernel headers (based on installed kernel).
- Bootloader setup: systemd-boot or GRUB.
- Enhanced Pacman (color, parallel downloads).
- System and mirrorlist updates.
- ZSH + Oh-My-ZSH + Starship prompt + plugins.
- Locale and timezone configuration.
- YAY (AUR helper) installation.
- Optional installation of popular programs (user-selected).
- Essential services enabled (networking, firewall, etc).
- Firewall setup (firewalld or ufw).
- Optional: Fail2ban, Virt-Manager.
- Cleans up unused packages and cache.
- Guided menu-based UI for installation options.
- Optional reboot after installation.

---

## ⚡ Quick Start

```bash
git clone https://github.com/gandromidas/archinstaller && cd archinstaller
chmod +x install.sh
./install.sh
```

Follow the interactive prompts to select:

- Default Installation
- Minimal Installation
- Exit

---

## 📒 Usage Details

- Run as root or with sudo privileges.
- The script will guide you through menu-driven choices for software and configuration.
- Supports both minimal and full-featured setups.
- Designed to be idempotent – safe to run multiple times.

---

## 🛠️ Script Details

### Key Variables

- `KERNEL_HEADERS`: Default Linux headers.
- Various directory path variables (`LOADER_DIR`, `ENTRIES_DIR`, etc).
- Color codes for enhanced terminal output.

### Main Functions

- `print_info`, `print_success`, `print_warning`, `print_error`: Informative colored output.
- `show_menu`: Main navigation.
- `install_kernel_headers`, `install_zsh`, `install_yay`, etc: Core install routines.
- `configure_pacman`, `update_mirrorlist`, `enable_services`, etc: System configuration steps.
- `install_and_configure_fail2ban`, `install_and_configure_virt_manager`: Optional extras.
- `clear_unused_packages_cache`, `delete_archinstaller_folder`, `reboot_system`: Maintenance and finish.

---

## ❓ FAQ & Troubleshooting

**Q:** Do I need to run this as root?  
**A:** Yes, the script requires root privileges.

**Q:** What if something fails?  
**A:** Check the error output in the terminal, and review the script logs if enabled.

**Q:** Can I customize what gets installed?  
**A:** Yes, the menu allows you to choose between installation sets, and you can further edit `install.sh` for more control.

---

## 🤝 Contributing

Contributions are welcome! Please fork this repository and submit a pull request.  
- Follow the existing code style.
- Add comments for clarity.
- See the [issues](https://github.com/GAndromidas/archinstaller/issues) page for ideas.

---

## 🔭 Roadmap

- [ ] Add more desktop environment options
- [ ] Community-driven configuration profiles
- [ ] Improved error logging and recovery
- [ ] Internationalization (i18n) support
- [ ] Automated CI testing

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by various Arch Linux setup guides and scripts.
- Special thanks to the Arch Linux community for their extensive documentation and support.

---

> _Enjoy your automated Arch Linux setup!_