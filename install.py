#!/usr/bin/env python3

import os
import sys
import subprocess
import shutil
import json
import platform
import glob
from pathlib import Path
from typing import List, Dict, Optional, Union
import logging
from dataclasses import dataclass
from enum import Enum
import time
import signal
import pwd
import grp
import re
import tempfile
import getpass

# Color codes for terminal output
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    RESET = '\033[0m'

class InstallMode(Enum):
    DEFAULT = "default"
    MINIMAL = "minimal"

# Embedded configuration files
CONFIGS = {
    ".zshrc": """# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# Aliases
alias ls='eza --icons'
alias ll='eza -l --icons'
alias la='eza -la --icons'
alias lt='eza -T --icons'

# Starship prompt
eval "$(starship init zsh)"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
""",

    "starship.toml": """# Starship configuration
format = '''
$username\
$hostname\
$directory\
$git_branch\
$git_status\
$cmd_duration\
$line_break\
$python\
$character'''

[directory]
style = "blue bold"
truncation_length = 3
truncate_to_repo = true

[git_branch]
format = "[$branch]($style) "
style = "green"

[git_status]
format = '([\[$all_status$ahead_behind\]]($style) )'
style = "yellow"

[cmd_duration]
format = "[$duration]($style) "
style = "yellow"

[python]
format = "[$virtualenv]($style) "
style = "green"

[character]
success_symbol = "[❯](green)"
error_symbol = "[❯](red)"
""",

    "config.jsonc": """{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "type": "small",
    "padding": {
      "left": 2,
      "right": 2
    },
    "margin": {
      "left": 2,
      "right": 2
    }
  },
  "display": {
    "separator": "  ",
    "keyWidth": 11,
    "title": {
      "text": "fastfetch",
      "color": "blue"
    }
  },
  "modules": [
    {
      "type": "os",
      "key": "OS",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "kernel",
      "key": "Kernel",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "packages",
      "key": "Packages",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "shell",
      "key": "Shell",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "de",
      "key": "DE",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "wm",
      "key": "WM",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "terminal",
      "key": "Terminal",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "cpu",
      "key": "CPU",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "gpu",
      "key": "GPU",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "memory",
      "key": "Memory",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "disk",
      "key": "Disk",
      "format": "{c1}{?} {c2}{v}"
    },
    {
      "type": "uptime",
      "key": "Uptime",
      "format": "{c1}{?} {c2}{v}"
    }
  ]
}"""
}

# Embedded script contents
SCRIPTS = {
    "setup_plymouth.sh": """#!/bin/bash
# Install Plymouth and themes
sudo pacman -S --noconfirm --needed plymouth plymouth-theme-arch-charge

# Configure Plymouth
sudo sed -i 's/^HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev plymouth autodetect modconf block filesystems keyboard fsck)/' /etc/mkinitcpio.conf

# Rebuild initramfs
sudo mkinitcpio -P

# Enable Plymouth service
sudo systemctl enable plymouth-start.service
""",

    "install_yay.sh": """#!/bin/bash
# Install yay AUR helper
git clone https://aur.archlinux.org/yay.git /tmp/yay
cd /tmp/yay
makepkg -si --noconfirm
""",

    "programs.sh": """#!/bin/bash
# Default packages
DEFAULT_PACKAGES=(
    # System utilities
    base-devel
    bluez-utils
    cronie
    curl
    eza
    fastfetch
    figlet
    flatpak
    fzf
    git
    openssh
    pacman-contrib
    reflector
    rsync
    ufw
    zoxide

    # Desktop environment
    plasma
    kde-applications
    sddm

    # Development tools
    code
    docker
    docker-compose
    nodejs
    npm
    python
    python-pip

    # Media
    vlc
    gimp
    inkscape

    # Internet
    firefox
    chromium
    telegram-desktop
    discord

    # Utilities
    htop
    neofetch
    screenfetch
    tree
    wget
)

# Minimal packages
MINIMAL_PACKAGES=(
    base-devel
    bluez-utils
    cronie
    curl
    eza
    fastfetch
    git
    openssh
    pacman-contrib
    reflector
    rsync
    ufw
    zoxide
)

# Install packages based on mode
if [ "$1" = "-m" ]; then
    sudo pacman -S --noconfirm --needed "${MINIMAL_PACKAGES[@]}"
else
    sudo pacman -S --noconfirm --needed "${DEFAULT_PACKAGES[@]}"
fi
""",

    "fail2ban.sh": """#!/bin/bash
# Install fail2ban
sudo pacman -S --noconfirm --needed fail2ban

# Configure fail2ban
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Enable and start fail2ban
sudo systemctl enable --now fail2ban
"""
}

# --- Package lists from programs.sh ---
PACMAN_PROGRAMS_DEFAULT = [
    # System utilities
    "android-tools", "bat", "bleachbit", "btop", "bluez-utils", "cmatrix", "dmidecode", "dosfstools", "expac", "firefox", "fwupd", "gamemode", "gnome-disk-utility", "hwinfo", "inxi", "lib32-gamemode", "lib32-mangohud", "mangohud", "net-tools", "noto-fonts-extra", "ntfs-3g", "samba", "sl", "speedtest-cli", "sshfs", "ttf-hack-nerd", "ttf-liberation", "unrar", "wget", "xdg-desktop-portal-gtk"
]
ESSENTIAL_PROGRAMS_DEFAULT = [
    "discord", "filezilla", "gimp", "kdenlive", "libreoffice-fresh", "lutris", "obs-studio", "steam", "telegram-desktop", "timeshift", "vlc", "wine"
]
PACMAN_PROGRAMS_MINIMAL = [
    "android-tools", "bat", "bleachbit", "btop", "bluez-utils", "cmatrix", "dmidecode", "dosfstools", "expac", "firefox", "fwupd", "gnome-disk-utility", "hwinfo", "inxi", "net-tools", "noto-fonts-extra", "ntfs-3g", "samba", "sl", "speedtest-cli", "sshfs", "ttf-hack-nerd", "ttf-liberation", "unrar", "wget", "xdg-desktop-portal-gtk"
]
ESSENTIAL_PROGRAMS_MINIMAL = [
    "libreoffice-fresh", "timeshift", "vlc"
]
KDE_INSTALL_PROGRAMS = ["gwenview", "kdeconnect", "kwalletmanager", "kvantum", "okular", "power-profiles-daemon", "python-pyqt5", "python-pyqt6", "qbittorrent", "spectacle"]
KDE_REMOVE_PROGRAMS = ["htop"]
GNOME_INSTALL_PROGRAMS = ["celluloid", "dconf-editor", "gnome-tweaks", "gufw", "seahorse", "transmission-gtk"]
GNOME_REMOVE_PROGRAMS = ["epiphany", "gnome-contacts", "gnome-maps", "gnome-music", "gnome-tour", "htop", "snapshot", "totem"]
COSMIC_INSTALL_PROGRAMS = ["power-profiles-daemon", "transmission-gtk"]
COSMIC_REMOVE_PROGRAMS = ["htop"]
YAY_PROGRAMS_DEFAULT = ["brave-bin", "heroic-games-launcher-bin", "megasync-bin", "spotify", "stacer-bin", "stremio", "teamviewer", "via-bin"]
YAY_PROGRAMS_MINIMAL = ["brave-bin", "stacer-bin", "stremio", "teamviewer"]
FLATPAK_KDE = ["io.github.shiftey.Desktop", "it.mijorus.gearlever", "net.davidotek.pupgui2"]
FLATPAK_GNOME = ["com.mattjakeman.ExtensionManager", "io.github.shiftey.Desktop", "it.mijorus.gearlever", "com.vysp3r.ProtonPlus"]
FLATPAK_COSMIC = ["io.github.shiftey.Desktop", "it.mijorus.gearlever", "com.vysp3r.ProtonPlus", "dev.edfloreshz.CosmicTweaks"]
FLATPAK_MINIMAL_KDE = ["it.mijorus.gearlever"]
FLATPAK_MINIMAL_GNOME = ["com.mattjakeman.ExtensionManager", "it.mijorus.gearlever"]
FLATPAK_MINIMAL_COSMIC = ["it.mijorus.gearlever", "dev.edfloreshz.CosmicTweaks"]
FLATPAK_MINIMAL_GENERIC = ["it.mijorus.gearlever"]

@dataclass
class InstallerConfig:
    script_dir: Path
    configs_dir: Path
    scripts_dir: Path
    install_mode: InstallMode
    errors: List[str] = None
    installed_packages: List[str] = None
    removed_packages: List[str] = None
    current_step: int = 1
    total_steps: int = 20

    def __post_init__(self):
        if self.errors is None:
            self.errors = []
        if self.installed_packages is None:
            self.installed_packages = []
        if self.removed_packages is None:
            self.removed_packages = []

class ArchInstaller:
    def __init__(self):
        self.config = InstallerConfig(
            script_dir=Path(__file__).parent.absolute(),
            configs_dir=Path(__file__).parent / "configs",
            scripts_dir=Path(__file__).parent / "scripts",
            install_mode=InstallMode.DEFAULT
        )
        self.helper_utils = [
            "base-devel", "bluez-utils", "cronie", "curl", "eza",
            "fastfetch", "figlet", "flatpak", "fzf", "git", "openssh",
            "pacman-contrib", "reflector", "rsync", "ufw", "zoxide"
        ]
        self.setup_logging()
        self.setup_directories()

    def setup_directories(self):
        """Create necessary directories and write config files"""
        # Create configs directory
        self.config.configs_dir.mkdir(exist_ok=True)
        
        # Create scripts directory
        self.config.scripts_dir.mkdir(exist_ok=True)
        
        # Write config files
        for filename, content in CONFIGS.items():
            config_file = self.config.configs_dir / filename
            if not config_file.exists():
                with open(config_file, 'w') as f:
                    f.write(content)
        
        # Write script files
        for filename, content in SCRIPTS.items():
            script_file = self.config.scripts_dir / filename
            if not script_file.exists():
                with open(script_file, 'w') as f:
                    f.write(content)
                script_file.chmod(0o755)

    def setup_logging(self):
        """Setup logging configuration"""
        log_file = self.config.script_dir / "install.log"
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler()
            ]
        )

    def print_colored(self, text: str, color: str, end: str = '\n'):
        """Print colored text to terminal"""
        print(f"{color}{text}{Colors.RESET}", end=end)

    def print_banner(self):
        """Print Arch Linux ASCII banner"""
        banner = """
      _             _     ___           _        _ _
     / \   _ __ ___| |__ |_ _|_ __  ___| |_ __ _| | | ___ _ __
    / _ \ | '__/ __| '_ \ | || '_ \/ __| __/ _` | | |/ _ \ '__|
   / ___ \| | | (__| | | || || | | \__ \ || (_| | | |  __/ |
  /_/   \_\_|  \___|_| |_|___|_| |_|___/\__\__,_|_|_|\___|_|
        """
        self.print_colored(banner, Colors.CYAN)

    def show_progress(self):
        """Show installation progress"""
        width = 40
        filled = int(width * (self.config.current_step - 1) / self.config.total_steps)
        empty = width - filled
        progress = f"[{'#' * filled}{' ' * empty}] {self.config.current_step - 1}/{self.config.total_steps}"
        self.print_colored(progress, Colors.CYAN)

    def step(self, description: str):
        """Print step description and update progress"""
        self.print_colored(f"\n[{self.config.current_step}] {description}", Colors.CYAN)
        self.show_progress()
        self.config.current_step += 1

    def run_command(self, command: List[str], check: bool = True) -> subprocess.CompletedProcess:
        """Run a shell command and return the result"""
        try:
            result = subprocess.run(
                command,
                check=check,
                capture_output=True,
                text=True
            )
            return result
        except subprocess.CalledProcessError as e:
            logging.error(f"Command failed: {' '.join(command)}")
            logging.error(f"Error: {e.stderr}")
            self.config.errors.append(f"Failed to execute: {' '.join(command)}")
            raise

    def check_prerequisites(self):
        """Check system prerequisites"""
        self.step("Checking system prerequisites")
        
        # Check if running as root
        if os.geteuid() == 0:
            self.print_colored("Do not run this script as root. Please run as a regular user with sudo privileges.", Colors.RED)
            sys.exit(1)

        # Check if pacman is available
        if not shutil.which("pacman"):
            self.print_colored("This script is intended for Arch Linux systems with pacman.", Colors.RED)
            sys.exit(1)

        self.print_colored("Prerequisites OK.", Colors.GREEN)

    def set_sudo_pwfeedback(self):
        """Enable password feedback in sudo"""
        self.step("Enabling sudo password feedback")
        try:
            if not os.path.exists("/etc/sudoers.d/pwfeedback"):
                self.run_command(["sudo", "bash", "-c", "echo 'Defaults env_reset,pwfeedback' > /etc/sudoers.d/pwfeedback"])
                self.print_colored("Password feedback enabled in sudo.", Colors.GREEN)
            else:
                self.print_colored("Password feedback already enabled.", Colors.YELLOW)
        except subprocess.CalledProcessError:
            self.print_colored("Failed to enable password feedback.", Colors.RED)

    def install_cpu_microcode(self):
        """Install CPU microcode"""
        self.step("Installing CPU microcode")
        try:
            with open("/proc/cpuinfo", "r") as f:
                cpu_info = f.read()
                if "Intel" in cpu_info:
                    self.install_packages(["intel-ucode"])
                elif "AMD" in cpu_info:
                    self.install_packages(["amd-ucode"])
                else:
                    self.print_colored("Unable to determine CPU type.", Colors.YELLOW)
        except Exception as e:
            self.print_colored(f"Error detecting CPU: {e}", Colors.RED)

    def install_kernel_headers_for_all(self):
        """Install kernel headers for all installed kernels"""
        self.step("Installing kernel headers")
        kernel_types = []
        for kernel in ["linux", "linux-lts", "linux-zen", "linux-hardened"]:
            if self.run_command(["pacman", "-Q", kernel], check=False).returncode == 0:
                kernel_types.append(kernel)
        
        if not kernel_types:
            self.print_colored("No supported kernel types detected.", Colors.YELLOW)
            return

        for kernel in kernel_types:
            self.install_packages([f"{kernel}-headers"])

    def generate_locales(self):
        """Generate system locales"""
        self.step("Generating locales")
        try:
            self.run_command(["sudo", "sed", "-i", "s/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/", "/etc/locale.gen"])
            self.run_command(["sudo", "locale-gen"])
            self.print_colored("Locales generated successfully.", Colors.GREEN)
        except subprocess.CalledProcessError:
            self.print_colored("Failed to generate locales.", Colors.RED)

    def make_systemd_boot_silent(self):
        """Make systemd-boot silent"""
        self.step("Configuring systemd-boot")
        entries_dir = Path("/boot/loader/entries")
        if not entries_dir.exists():
            self.print_colored("Systemd-boot entries directory not found.", Colors.YELLOW)
            return

        for entry in entries_dir.glob("*.conf"):
            if "fallback" not in entry.name:
                try:
                    self.run_command([
                        "sudo", "sed", "-i",
                        "/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/",
                        str(entry)
                    ])
                except subprocess.CalledProcessError:
                    self.print_colored(f"Failed to modify entry: {entry.name}", Colors.RED)

    def change_loader_conf(self):
        """Change loader.conf settings"""
        self.step("Updating loader configuration")
        loader_conf = Path("/boot/loader/loader.conf")
        if not loader_conf.exists():
            self.print_colored("loader.conf not found.", Colors.YELLOW)
            return

        try:
            # Set default entry
            self.run_command(["sudo", "sed", "-i", "/^default /d", str(loader_conf)])
            self.run_command(["sudo", "sed", "-i", "1i default @saved", str(loader_conf)])

            # Set timeout
            if self.run_command(["grep", "^timeout", str(loader_conf)], check=False).returncode == 0:
                self.run_command(["sudo", "sed", "-i", "s/^timeout.*/timeout 3/", str(loader_conf)])
            else:
                self.run_command(["sudo", "bash", "-c", f"echo 'timeout 3' >> {loader_conf}"])

            # Set console mode
            self.run_command([
                "sudo", "sed", "-i",
                "s/^[#]*console-mode[[:space:]]\+.*/console-mode max/",
                str(loader_conf)
            ])

            self.print_colored("Loader configuration updated.", Colors.GREEN)
        except subprocess.CalledProcessError:
            self.print_colored("Failed to update loader configuration.", Colors.RED)

    def remove_fallback_entries(self):
        """Remove fallback entries from systemd-boot"""
        self.step("Removing fallback entries")
        entries_dir = Path("/boot/loader/entries")
        if not entries_dir.exists():
            self.print_colored("Systemd-boot entries directory not found.", Colors.YELLOW)
            return

        entries_removed = False
        for entry in entries_dir.glob("*fallback.conf"):
            try:
                self.run_command(["sudo", "rm", str(entry)])
                self.print_colored(f"Removed fallback entry: {entry.name}", Colors.GREEN)
                entries_removed = True
            except subprocess.CalledProcessError:
                self.print_colored(f"Failed to remove fallback entry: {entry.name}", Colors.RED)

        if not entries_removed:
            self.print_colored("No fallback entries found.", Colors.YELLOW)

    def setup_fastfetch_config(self):
        """Setup fastfetch configuration"""
        self.step("Setting up fastfetch")
        if not shutil.which("fastfetch"):
            self.print_colored("fastfetch not installed.", Colors.YELLOW)
            return

        config_dir = Path.home() / ".config/fastfetch"
        config_file = config_dir / "config.jsonc"

        if not config_file.exists():
            try:
                self.run_command(["fastfetch", "--gen-config"])
                self.print_colored("Fastfetch config generated.", Colors.GREEN)
            except subprocess.CalledProcessError:
                self.print_colored("Failed to generate fastfetch config.", Colors.RED)
        else:
            self.print_colored("Fastfetch config already exists.", Colors.YELLOW)

    def install_packages(self, packages: List[str], quiet: bool = False):
        """Install packages using pacman"""
        for pkg in packages:
            # Check if package is already installed
            result = self.run_command(["pacman", "-Q", pkg], check=False)
            if result.returncode == 0:
                if not quiet:
                    self.print_colored(f"Installing: {pkg} ... [SKIP] Already installed", Colors.YELLOW)
                continue

            if not quiet:
                self.print_colored(f"Installing: {pkg} ...", Colors.CYAN, end=" ")

            try:
                self.run_command(["sudo", "pacman", "-S", "--noconfirm", "--needed", pkg])
                if not quiet:
                    self.print_colored("[OK]", Colors.GREEN)
                self.config.installed_packages.append(pkg)
            except subprocess.CalledProcessError:
                if not quiet:
                    self.print_colored("[FAIL]", Colors.RED)
                self.config.errors.append(f"Failed to install {pkg}")

    def configure_pacman(self):
        """Configure pacman settings"""
        self.step("Configuring Pacman")
        
        # Enable color output
        self.run_command(["sudo", "sed", "-i", "s/^#Color/Color/", "/etc/pacman.conf"])
        
        # Enable verbose package lists
        self.run_command(["sudo", "sed", "-i", "s/^#VerbosePkgLists/VerbosePkgLists/", "/etc/pacman.conf"])
        
        # Enable parallel downloads
        self.run_command(["sudo", "sed", "-i", "s/^#ParallelDownloads/ParallelDownloads/", "/etc/pacman.conf"])
        
        # Enable ILoveCandy
        self.run_command(["sudo", "sed", "-i", "/^Color/a ILoveCandy", "/etc/pacman.conf"])
        
        # Enable multilib repository
        if not self._is_multilib_enabled():
            self.run_command(["sudo", "sed", "-i", "/^#\\[multilib\\]/,/^#Include/s/^#//", "/etc/pacman.conf"])
        
        self.print_colored("Pacman configuration completed.", Colors.GREEN)

    def _is_multilib_enabled(self) -> bool:
        """Check if multilib repository is enabled"""
        try:
            with open("/etc/pacman.conf", "r") as f:
                content = f.read()
                return "[multilib]" in content and not "#[multilib]" in content
        except Exception as e:
            logging.error(f"Error checking multilib status: {e}")
            return False

    def update_mirrors_and_system(self):
        """Update mirrorlist and system packages"""
        self.step("Updating mirrorlist and system")
        
        # Update mirrorlist using reflector
        self.run_command([
            "sudo", "reflector",
            "--verbose",
            "--protocol", "https",
            "--latest", "5",
            "--sort", "rate",
            "--save", "/etc/pacman.d/mirrorlist"
        ])
        
        # Update system
        self.run_command(["sudo", "pacman", "-Syyu", "--noconfirm"])
        
        self.print_colored("System updated successfully.", Colors.GREEN)

    def setup_zsh(self):
        """Setup ZSH shell and Oh-My-Zsh"""
        self.step("Setting up ZSH")
        
        # Install ZSH and plugins
        self.install_packages(["zsh", "zsh-autosuggestions", "zsh-syntax-highlighting"])
        
        # Install Oh-My-Zsh if not already installed
        if not (Path.home() / ".oh-my-zsh").exists():
            self.run_command([
                "sh", "-c",
                'RUNZSH=no CHSH=no KEEP_ZSHRC=yes yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
            ])
        
        # Change default shell to ZSH
        self.run_command(["sudo", "chsh", "-s", shutil.which("zsh"), os.getenv("USER")])
        
        # Copy custom .zshrc if available
        custom_zshrc = self.config.configs_dir / ".zshrc"
        if custom_zshrc.exists():
            shutil.copy2(custom_zshrc, Path.home() / ".zshrc")
        
        self.print_colored("ZSH setup completed.", Colors.GREEN)

    def install_starship(self):
        """Install and configure Starship prompt"""
        self.step("Installing Starship prompt")
        
        # Install starship
        self.install_packages(["starship"])
        
        # Create config directory if it doesn't exist
        starship_config_dir = Path.home() / ".config"
        starship_config_dir.mkdir(exist_ok=True)
        
        # Copy starship config if available
        custom_starship = self.config.configs_dir / "starship.toml"
        if custom_starship.exists():
            shutil.copy2(custom_starship, starship_config_dir / "starship.toml")
        
        self.print_colored("Starship prompt setup completed.", Colors.GREEN)

    def detect_desktop_environment(self):
        de = os.environ.get("XDG_CURRENT_DESKTOP", "")
        if "KDE" in de:
            return "KDE"
        elif "GNOME" in de:
            return "GNOME"
        elif "COSMIC" in de:
            return "COSMIC"
        else:
            return "GENERIC"

    def ensure_yay(self):
        if not shutil.which("yay"):
            self.print_colored("yay (AUR helper) not found. Installing yay...", Colors.YELLOW)
            self.run_command(["bash", str(self.config.scripts_dir / "install_yay.sh")])
        else:
            self.print_colored("yay is already installed.", Colors.GREEN)

    def ensure_flatpak(self):
        if not shutil.which("flatpak"):
            self.print_colored("flatpak is not installed. Installing flatpak...", Colors.YELLOW)
            self.install_packages(["flatpak"])
        # Add Flathub remote if not present
        result = subprocess.run(["flatpak", "remote-list"], capture_output=True, text=True)
        if "flathub" not in result.stdout:
            self.print_colored("Adding Flathub remote...", Colors.YELLOW)
            self.run_command(["flatpak", "remote-add", "--if-not-exists", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo"])
        self.run_command(["flatpak", "update", "-y"])

    def install_flatpaks(self, flatpak_list):
        for pkg in flatpak_list:
            result = subprocess.run(["flatpak", "list", "--app"], capture_output=True, text=True)
            if pkg in result.stdout:
                self.print_colored(f"Flatpak: {pkg} ... [SKIP] Already installed", Colors.YELLOW)
                continue
            self.print_colored(f"Flatpak: {pkg} ...", Colors.CYAN, end=" ")
            try:
                self.run_command(["flatpak", "install", "-y", "--noninteractive", "flathub", pkg])
                self.print_colored("[OK]", Colors.GREEN)
            except subprocess.CalledProcessError:
                self.print_colored("[FAIL]", Colors.RED)
                self.config.errors.append(f"Failed to install Flatpak {pkg}")

    def install_aur_packages(self, aur_list):
        for pkg in aur_list:
            result = self.run_command(["pacman", "-Q", pkg], check=False)
            if result.returncode == 0:
                self.print_colored(f"AUR: {pkg} ... [SKIP] Already installed", Colors.YELLOW)
                continue
            self.print_colored(f"AUR: {pkg} ...", Colors.CYAN, end=" ")
            try:
                self.run_command(["yay", "-S", "--noconfirm", "--needed", pkg])
                self.print_colored("[OK]", Colors.GREEN)
            except subprocess.CalledProcessError:
                self.print_colored("[FAIL]", Colors.RED)
                self.config.errors.append(f"Failed to install AUR {pkg}")

    def install_user_programs(self):
        self.step("Installing user programs (native Python)")
        de = self.detect_desktop_environment()
        mode = self.config.install_mode
        # Pacman
        if mode == InstallMode.DEFAULT:
            pacman_pkgs = PACMAN_PROGRAMS_DEFAULT + ESSENTIAL_PROGRAMS_DEFAULT
            aur_pkgs = YAY_PROGRAMS_DEFAULT
            if de == "KDE":
                pacman_pkgs += KDE_INSTALL_PROGRAMS
            elif de == "GNOME":
                pacman_pkgs += GNOME_INSTALL_PROGRAMS
            elif de == "COSMIC":
                pacman_pkgs += COSMIC_INSTALL_PROGRAMS
        else:
            pacman_pkgs = PACMAN_PROGRAMS_MINIMAL + ESSENTIAL_PROGRAMS_MINIMAL
            aur_pkgs = YAY_PROGRAMS_MINIMAL
            if de == "KDE":
                pacman_pkgs += []  # No minimal KDE extras
            elif de == "GNOME":
                pacman_pkgs += []  # No minimal GNOME extras
            elif de == "COSMIC":
                pacman_pkgs += []  # No minimal COSMIC extras
        # Remove DE-specific packages if needed
        if de == "KDE":
            for pkg in KDE_REMOVE_PROGRAMS:
                self.run_command(["sudo", "pacman", "-Rns", "--noconfirm", pkg], check=False)
        elif de == "GNOME":
            for pkg in GNOME_REMOVE_PROGRAMS:
                self.run_command(["sudo", "pacman", "-Rns", "--noconfirm", pkg], check=False)
        elif de == "COSMIC":
            for pkg in COSMIC_REMOVE_PROGRAMS:
                self.run_command(["sudo", "pacman", "-Rns", "--noconfirm", pkg], check=False)
        # Install pacman packages
        self.install_packages(pacman_pkgs)
        # Flatpak
        self.ensure_flatpak()
        if mode == InstallMode.DEFAULT:
            if de == "KDE":
                self.install_flatpaks(FLATPAK_KDE)
            elif de == "GNOME":
                self.install_flatpaks(FLATPAK_GNOME)
            elif de == "COSMIC":
                self.install_flatpaks(FLATPAK_COSMIC)
        else:
            if de == "KDE":
                self.install_flatpaks(FLATPAK_MINIMAL_KDE)
            elif de == "GNOME":
                self.install_flatpaks(FLATPAK_MINIMAL_GNOME)
            elif de == "COSMIC":
                self.install_flatpaks(FLATPAK_MINIMAL_COSMIC)
            else:
                self.install_flatpaks(FLATPAK_MINIMAL_GENERIC)
        # AUR
        self.ensure_yay()
        self.install_aur_packages(aur_pkgs)

    def run_custom_scripts(self):
        """Run custom installation scripts (except user programs)"""
        self.step("Running custom scripts")
        # Setup Plymouth
        plymouth_script = self.config.scripts_dir / "setup_plymouth.sh"
        if plymouth_script.exists():
            plymouth_script.chmod(0o755)
            self.run_command([str(plymouth_script)])
        # Install Yay (if not present)
        yay_script = self.config.scripts_dir / "install_yay.sh"
        if yay_script.exists() and not shutil.which("yay"):
            yay_script.chmod(0o755)
            self.run_command([str(yay_script)])
        # Setup fail2ban
        fail2ban_script = self.config.scripts_dir / "fail2ban.sh"
        if fail2ban_script.exists():
            fail2ban_script.chmod(0o755)
            self.run_command([str(fail2ban_script)])
        self.print_colored("Custom scripts execution completed.", Colors.GREEN)

    def detect_and_install_gpu_drivers(self):
        """Detect GPU and install appropriate drivers"""
        self.step("Detecting GPU and installing drivers")
        
        # Get GPU information
        try:
            gpu_info = self.run_command(["lspci"]).stdout
        except subprocess.CalledProcessError:
            self.print_colored("Failed to get GPU information.", Colors.RED)
            return
        
        if "NVIDIA" in gpu_info:
            self._handle_nvidia_installation()
        elif "AMD" in gpu_info:
            self.install_packages(["xf86-video-amdgpu", "mesa"])
        elif "Intel" in gpu_info:
            self.install_packages(["mesa", "xf86-video-intel"])
        else:
            self.print_colored("No supported GPU detected.", Colors.YELLOW)

    def _handle_nvidia_installation(self):
        """Handle NVIDIA driver installation"""
        self.print_colored("NVIDIA GPU detected!", Colors.YELLOW)
        print("Choose a driver to install:")
        print("  1) Latest proprietary (nvidia-dkms)")
        print("  2) Legacy 390xx (AUR, very old cards)")
        print("  3) Legacy 340xx (AUR, ancient cards)")
        print("  4) Open-source Nouveau (recommended for unsupported/old cards)")
        print("  5) Skip GPU driver installation")
        
        choice = input("Enter your choice [1-5, default 4]: ").strip()
        
        if choice == "1":
            self.install_packages(["nvidia-dkms", "nvidia-utils"])
        elif choice == "2":
            self.run_command(["yay", "-S", "--noconfirm", "--needed", "nvidia-390xx-dkms", "nvidia-390xx-utils", "lib32-nvidia-390xx-utils"])
        elif choice == "3":
            self.run_command(["yay", "-S", "--noconfirm", "--needed", "nvidia-340xx-dkms", "nvidia-340xx-utils", "lib32-nvidia-340xx-utils"])
        elif choice == "5":
            self.print_colored("Skipping NVIDIA driver installation.", Colors.YELLOW)
        else:
            self.install_packages(["xf86-video-nouveau", "mesa"])

    def setup_firewall_and_services(self):
        """Setup firewall and system services"""
        self.step("Setting up firewall and services")
        
        # Install and configure UFW
        self.install_packages(["ufw"])
        self.run_command(["sudo", "ufw", "enable"])
        self.run_command(["sudo", "ufw", "default", "deny", "incoming"])
        self.run_command(["sudo", "ufw", "default", "allow", "outgoing"])
        self.run_command(["sudo", "ufw", "allow", "ssh"])
        
        # Enable system services
        services = [
            "bluetooth.service",
            "cronie.service",
            "ufw.service",
            "fstrim.timer",
            "paccache.timer",
            "reflector.service",
            "reflector.timer",
            "sshd.service",
            "teamviewerd.service",
            "power-profiles-daemon.service"
        ]
        
        for service in services:
            try:
                self.run_command(["sudo", "systemctl", "enable", "--now", service])
            except subprocess.CalledProcessError:
                logging.warning(f"Failed to enable service: {service}")
        
        self.print_colored("Firewall and services setup completed.", Colors.GREEN)

    def cleanup_and_optimize(self):
        """Perform final cleanup and optimizations"""
        self.step("Performing final cleanup and optimizations")
        
        # Run fstrim on SSDs
        if self._is_ssd():
            self.run_command(["sudo", "fstrim", "-v", "/"])
        
        # Clean /tmp directory
        self.run_command(["sudo", "rm", "-rf", "/tmp/*"])
        
        # Clean yay build directory
        self.run_command(["sudo", "rm", "-rf", "/tmp/yay"])
        
        # Remove temporary directories if no errors occurred
        if not self.config.errors:
            try:
                shutil.rmtree(self.config.configs_dir)
                shutil.rmtree(self.config.scripts_dir)
            except Exception as e:
                logging.warning(f"Failed to remove temporary directories: {e}")
        
        # Sync disk writes
        self.run_command(["sync"])
        
        self.print_colored("Cleanup and optimization completed.", Colors.GREEN)

    def _is_ssd(self) -> bool:
        """Check if root filesystem is on SSD"""
        try:
            result = self.run_command(["lsblk", "-d", "-o", "rota"]).stdout
            return "0" in result
        except subprocess.CalledProcessError:
            return False

    def print_summary(self):
        """Print installation summary"""
        self.print_colored("\n========= INSTALL SUMMARY =========", Colors.CYAN)
        
        if self.config.installed_packages:
            self.print_colored(f"Installed: {' '.join(self.config.installed_packages)}", Colors.GREEN)
        else:
            self.print_colored("No new packages were installed.", Colors.YELLOW)
        
        if self.config.removed_packages:
            self.print_colored(f"Removed: {' '.join(self.config.removed_packages)}", Colors.RED)
        else:
            self.print_colored("No packages were removed.", Colors.GREEN)
        
        if self.config.errors:
            self.print_colored("\nThe following steps failed:", Colors.RED)
            for error in self.config.errors:
                self.print_colored(f"  - {error}", Colors.YELLOW)
            self.print_colored(f"\nCheck the install log for more details: {self.config.script_dir}/install.log", Colors.YELLOW)
        else:
            self.print_colored("\nAll steps completed successfully!", Colors.GREEN)

    def prompt_reboot(self):
        """Prompt user to reboot the system"""
        self.print_colored("\nSetup is complete. It's strongly recommended to reboot your system now.", Colors.YELLOW)
        self.print_colored(f"If you encounter issues, review the install log: {self.config.script_dir}/install.log", Colors.CYAN)
        
        while True:
            choice = input("Reboot now? [Y/n]: ").strip().lower()
            if choice in ["", "y", "yes"]:
                self.print_colored("\nRebooting...", Colors.CYAN)
                self.run_command(["sudo", "reboot"])
                break
            elif choice in ["n", "no"]:
                self.print_colored("\nReboot skipped. You can reboot manually at any time using `sudo reboot`.", Colors.YELLOW)
                break
            else:
                self.print_colored("\nPlease answer Y (yes) or N (no).", Colors.RED)

    def main(self):
        self.print_banner()
        self.show_menu()
        self.config.current_step = 1
        self.print_colored("\nPlease enter your sudo password to begin the installation (it will not be echoed):", Colors.YELLOW)
        try:
            subprocess.run(["sudo", "-v"], check=True)
        except subprocess.CalledProcessError:
            self.print_colored("Incorrect password or sudo privileges required. Exiting.", Colors.RED)
            sys.exit(1)
        def keep_sudo_alive():
            while True:
                try:
                    subprocess.run(["sudo", "-n", "true"], check=True)
                    time.sleep(60)
                except (subprocess.CalledProcessError, KeyboardInterrupt):
                    break
        import threading
        sudo_thread = threading.Thread(target=keep_sudo_alive, daemon=True)
        sudo_thread.start()
        logging.info(f"Starting installation with mode: {self.config.install_mode.value}")
        self.check_prerequisites()
        self.set_sudo_pwfeedback()
        self.install_packages(self.helper_utils)
        self.configure_pacman()
        self.update_mirrors_and_system()
        self.install_cpu_microcode()
        self.install_kernel_headers_for_all()
        self.generate_locales()
        self.setup_zsh()
        self.install_starship()
        self.run_custom_scripts()
        self.make_systemd_boot_silent()
        self.change_loader_conf()
        self.remove_fallback_entries()
        self.setup_fastfetch_config()
        self.detect_and_install_gpu_drivers()
        self.setup_firewall_and_services()
        self.install_user_programs()
        self.cleanup_and_optimize()
        self.print_summary()
        self.prompt_reboot()

if __name__ == "__main__":
    installer = ArchInstaller()
    installer.main() 