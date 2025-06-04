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

**archinstaller** is a modular, user-friendly, and highly customizable post-install script for Arch Linux. It automates essential system configuration, package installation, and desktop setup, allowing you to get a fully working system in minutes.

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

- **Modular, step-wise, and color-coded scripts for system and user program setup**
- Installs kernel headers for all installed kernels (linux, lts, zen, hardened)
- Bootloader tweaks (systemd-boot)
- Enhanced Pacman configuration (color, parallel downloads, ILoveCandy)
- Mirrorlist ranking via reflector
- ZSH + Oh-My-ZSH + Starship prompt + plugins
- Locales and timezone configuration
- **YAY (AUR helper) installed via its own standalone script** (`scripts/install_yay.sh`)
- **User program installation is fully flag-driven** (`-d` for Default, `-m` for Minimal)  
  - No interactive menu in `programs.sh`—mode is set from the top-level `install.sh`
  - Desktop environment detection; minimal set fallback for unknown DE/WM
- AUR and Flatpak program installation, with improved error handling and summary
- Optional: Fail2ban and Plymouth each have their own robust scripts in `scripts/`
- Firewall setup (ufw)
- Service enablement (Bluetooth, cron, ufw, fstrim, etc)
- System maintenance: cache cleaning, orphans removal, SSD trim
- Guided menu-based UI for install mode in `install.sh` only
- Optional reboot after installation
- **All major sub-scripts (`fail2ban.sh`, `setup_plymouth.sh`, etc) use the same color-coded, step-wise logic as the main installer**
- **Idempotent:** Safe to run multiple times; only acts when needed
- **No password reprompt:** Sudo session is kept alive throughout install

---

## ⚡ Quick Start

```bash
git clone https://github.com/gandromidas/archinstaller && cd archinstaller
chmod +x install.sh
./install.sh
```

Follow the interactive prompts in `install.sh` to select:

- Default Installation (full-featured, recommended)
- Minimal Installation (core utilities only)
- Exit

---

## 📒 Usage Details

- Run as root or with sudo privileges.
- `install.sh` guides you through all high-level choices.
- User program installation mode (Default/Minimal) is only chosen in `install.sh` and passed as a flag to `programs.sh`. No duplicate prompts.
- All sub-scripts (`programs.sh`, `fail2ban.sh`, `setup_plymouth.sh`, etc) are modular and use robust output and logging, matching the main installer.
- Designed to be idempotent—safe to run multiple times.

---

## 🛠️ Script Details

### Structure

- **install.sh**: Main orchestrator. Handles all sudo, system prep, user interaction, and delegates to sub-scripts.
- **scripts/install_yay.sh**: Installs yay AUR helper independently (modular, no password reprompt).
- **scripts/programs.sh**: Handles user-level and DE-specific program installation. Accepts `-d` (Default) or `-m` (Minimal) flag only—no internal menu. Handles Flatpak, Pacman, and AUR.
- **scripts/fail2ban.sh**: Full step-wise install/configure with robust output.
- **scripts/setup_plymouth.sh**: Step-wise Plymouth install and configuration.
- **configs/**: Contains sample configs for shell, starship prompt, fastfetch, etc.

### Main Logic

- Colored, step-wise logging for all scripts.
- Sudo session is kept alive throughout install.
- All critical actions (install, enable, configure) are modular functions.
- Error handling and summary at the end for every script.
- Programs and services are only installed/enabled if not already present.
- Automatic fallback to minimal set for unknown DE/WM in `programs.sh` if Default is chosen.
- All script flags and menus are at the top-level (`install.sh`).

---

## ❓ FAQ & Troubleshooting

**Q:** Do I need to run this as root?  
**A:** Yes, the script requires root privileges.

**Q:** What if something fails?  
**A:** Check the error output in the terminal, and review the script logs if enabled.

**Q:** Can I customize what gets installed?  
**A:** Yes, the menu allows you to choose between installation sets, and you can further edit `install.sh` and `programs.sh` for more control.

**Q:** Does the user program installer (`programs.sh`) prompt me for install mode?  
**A:** No, you choose Default or Minimal in `install.sh` only. `programs.sh` receives the mode as a flag (`-d` or `-m`).

---

## 🤝 Contributing

Contributions are welcome! Please fork this repository and submit a pull request.  
- Follow the existing code style.
- Add comments for clarity.
- See the [issues](https://github.com/GAndromidas/archinstaller/issues) page for ideas.

---

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Inspired by various Arch Linux setup guides and scripts.
- Special thanks to the Arch Linux community for their extensive documentation and support.

---

> _Enjoy your automated Arch Linux setup!_
