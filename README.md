# Archinstaller: Arch Linux Post-Installation Script

[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![Total Downloads](https://img.shields.io/github/downloads/GAndromidas/archinstaller/total.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/releases)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/archinstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/archinstaller/commits/main)

---

## 🎬 Demo

[![YouTube Video](https://img.shields.io/badge/YouTube-Video-red)](https://www.youtube.com/watch?v=lWoKlybEjeU)

![archinstaller](https://github.com/user-attachments/assets/72ff3e94-dd8d-4e18-8c13-30f8b6ba4ef6)

---

## Overview

**Archinstaller** automates your Arch Linux post-install setup. It configures your system, installs essential and optional packages, and customizes your desktop environment—all with minimal user input.

- **Two modes:** Default (full setup) or Minimal (core utilities)
- **Automatic DE detection:** KDE, GNOME, Cosmic, or fallback
- **Idempotent:** Safe to run multiple times

---

## Quick Start

```bash
git clone https://github.com/gandromidas/archinstaller && cd archinstaller
chmod +x install.sh
./install.sh
```

- Run as a regular user with sudo privileges.
- Follow the interactive menu.

---

## Features

- Optimizes Pacman and mirrorlist
- Installs CPU microcode, kernel headers, and configures locale/timezone
- Sets up UFW firewall and system services
- Installs YAY (AUR helper) and Flatpak (with Flathub)
- Installs packages based on your desktop environment and chosen mode
- Optional: Fail2ban, Plymouth, and more

---

## Structure

- `install.sh` — Main script
- `scripts/` — Modular sub-scripts (YAY, programs, fail2ban, plymouth, etc.)
- `configs/` — Config templates

---

## Customization

- Edit package lists in `scripts/programs.sh` for custom installs.
- Choose between Default and Minimal modes at launch.

---

## FAQ

- **Run as root?** No, use a regular user with sudo.
- **Something failed?** Check the terminal output for errors.
- **Supported DEs?** KDE, GNOME, Cosmic. Others get a minimal set.

---

## Contributing

Pull requests are welcome! Please follow the code style and add comments where needed.

---

## License

MIT — see [LICENSE](LICENSE).

---

_Enjoy your automated Arch Linux setup!_
