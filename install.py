#!/usr/bin/env python3
"""
ArchInstaller - Python Edition
Comprehensive Arch Linux Post-Installation Setup
"""

import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

# --- Global Constants ---
ROOT_DIR = Path(__file__).parent.resolve()
CONFIG_DIR = ROOT_DIR / "configs"
LOG_FILE = Path.home() / ".archinstaller.log"
STATE_FILE = Path.home() / ".archinstaller.state"


# --- Bootstrapping Dependencies ---
def bootstrap_dependencies():
    """Ensure required Python packages are installed."""
    required = ["rich", "yaml"]
    missing = []

    for pkg in required:
        try:
            if pkg == "yaml":
                import yaml
            elif pkg == "rich":
                import rich
        except ImportError:
            missing.append(f"python-{pkg}" if pkg == "yaml" else f"python-{pkg}")

    if missing:
        print(f"Installing missing dependencies: {', '.join(missing)}...")
        try:
            subprocess.run(
                ["sudo", "pacman", "-S", "--noconfirm", "--needed"] + missing,
                check=True,
            )
            print("Dependencies installed. Restarting script...")
            os.execv(sys.executable, [sys.executable] + sys.argv)
        except subprocess.CalledProcessError:
            print(
                "Failed to install dependencies. Please run: sudo pacman -S python-rich python-pyyaml"
            )
            sys.exit(1)


bootstrap_dependencies()

# Imports after bootstrap
import yaml
from rich import print as rprint
from rich.console import Console
from rich.logging import RichHandler
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.prompt import Confirm, Prompt
from rich.table import Table
from rich.text import Text

# --- Logging Setup ---
logging.basicConfig(
    level="INFO",
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, mode="a"),
    ],
)
logger = logging.getLogger("ArchInstaller")
console = Console()


# --- Utility Classes ---
class Utils:
    @staticmethod
    def run_command(
        cmd: List[str],
        sudo: bool = False,
        check: bool = True,
        quiet: bool = True,
        timeout: int = None,
    ) -> subprocess.CompletedProcess:
        """Execute a shell command safely."""
        if sudo and os.geteuid() != 0:
            cmd = ["sudo"] + cmd

        cmd_str = " ".join(cmd)
        logger.info(f"Executing: {cmd_str}")

        try:
            result = subprocess.run(
                cmd,
                check=check,
                stdout=subprocess.PIPE if quiet else None,
                stderr=subprocess.PIPE if quiet else None,
                text=True,
                timeout=timeout,
            )
            return result
        except subprocess.CalledProcessError as e:
            logger.error(f"Command failed: {cmd_str}")
            if quiet:
                logger.error(f"Stderr: {e.stderr}")
            if check:
                raise
            return e
        except subprocess.TimeoutExpired:
            logger.error(f"Command timed out: {cmd_str}")
            if check:
                raise
            return subprocess.CompletedProcess(cmd, 1, "", "Timeout")

    @staticmethod
    def check_internet() -> bool:
        try:
            urllib.request.urlopen("https://archlinux.org", timeout=3)
            return True
        except:
            return False

    @staticmethod
    def sed_replace(file_path: Path, pattern: str, replacement: str, sudo: bool = True):
        """Sed-like replacement in a file."""
        cmd = ["sed", "-i", f"s|{pattern}|{replacement}|g", str(file_path)]
        Utils.run_command(cmd, sudo=sudo)

    @staticmethod
    def append_to_file(file_path: Path, content: str, sudo: bool = True):
        """Append text to a file."""
        if sudo:
            cmd = f"echo '{content}' | sudo tee -a {file_path}"
            subprocess.run(cmd, shell=True, check=True, stdout=subprocess.DEVNULL)
        else:
            with open(file_path, "a") as f:
                f.write(content + "\n")


class SystemProbe:
    """Hardware and System Detection logic."""

    def __init__(self):
        self.cpu_vendor = self._detect_cpu()
        self.gpu_vendor = self._detect_gpu()
        self.is_laptop = self._detect_laptop()
        self.ram_gb = self._detect_ram()
        self.is_vm = self._detect_vm()
        self.desktop_env = os.environ.get("XDG_CURRENT_DESKTOP", "Unknown")
        self.bootloader = self._detect_bootloader()
        self.filesystem = self._detect_filesystem()

    def _detect_cpu(self) -> str:
        try:
            with open("/proc/cpuinfo") as f:
                content = f.read()
                if "GenuineIntel" in content:
                    return "intel"
                if "AuthenticAMD" in content:
                    return "amd"
        except:
            pass
        return "unknown"

    def _detect_gpu(self) -> str:
        try:
            lspci = subprocess.check_output("lspci", shell=True, text=True).lower()
            if "nvidia" in lspci:
                return "nvidia"
            if "amd" in lspci and ("vga" in lspci or "display" in lspci):
                return "amd"
            if "intel" in lspci and ("vga" in lspci or "display" in lspci):
                return "intel"
        except:
            pass
        return "unknown"

    def _detect_laptop(self) -> bool:
        try:
            if os.path.exists("/sys/class/dmi/id/chassis_type"):
                with open("/sys/class/dmi/id/chassis_type") as f:
                    type_code = int(f.read().strip())
                    return type_code in [8, 9, 10, 14]
            return os.path.exists("/sys/class/power_supply/BAT0")
        except:
            return False

    def _detect_ram(self) -> int:
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if "MemTotal" in line:
                        kb = int(line.split()[1])
                        return kb // (1024 * 1024)
        except:
            pass
        return 0

    def _detect_vm(self) -> bool:
        try:
            res = subprocess.run(
                ["systemd-detect-virt"], capture_output=True, text=True
            )
            return res.stdout.strip() != "none"
        except:
            return False

    def _detect_bootloader(self) -> str:
        if Path("/boot/loader/entries").exists():
            return "systemd-boot"
        if Path("/boot/grub/grub.cfg").exists() or Path("/etc/default/grub").exists():
            return "grub"
        return "unknown"

    def _detect_filesystem(self) -> str:
        try:
            res = subprocess.run(
                ["findmnt", "-no", "FSTYPE", "/"], capture_output=True, text=True
            )
            return res.stdout.strip()
        except:
            return "unknown"


class ConfigLoader:
    """Loads YAML configurations."""

    def __init__(self, config_path: Path):
        self.config_path = config_path
        self.data = {}
        self.load()

    def load(self):
        if not self.config_path.exists():
            logger.error(f"Config file not found: {self.config_path}")
            return
        with open(self.config_path) as f:
            self.data = yaml.safe_load(f)

    def get_packages(
        self, mode: str, category: str, subcategory: str = None
    ) -> List[str]:
        try:
            section = self.data.get(category, {})
            target = section.get(subcategory, []) if subcategory else section

            if isinstance(target, dict):
                if mode in target:
                    target = target[mode]
                elif "packages" in target:
                    target = target["packages"]

            if not target:
                return []

            packages = []
            for item in target:
                if isinstance(item, str):
                    packages.append(item)
                elif isinstance(item, dict) and "name" in item:
                    packages.append(item["name"])
            return packages
        except Exception as e:
            logger.error(f"Error parsing config for {category}/{subcategory}: {e}")
            return []


class PackageManager:
    """Handles pacman, yay, and flatpak operations."""

    def __init__(self):
        self.failed_packages = []

    def ensure_yay(self):
        """Bootstrap yay if missing."""
        if shutil.which("yay"):
            return

        console.print(Panel("Installing yay AUR helper...", style="cyan"))
        try:
            # Ensure base-devel and git
            Utils.run_command(
                ["pacman", "-S", "--noconfirm", "--needed", "base-devel", "git"],
                sudo=True,
            )

            with tempfile.TemporaryDirectory() as tmpdirname:
                clone_dir = Path(tmpdirname) / "yay"
                # Clone as non-root
                Utils.run_command(
                    [
                        "git",
                        "clone",
                        "https://aur.archlinux.org/yay.git",
                        str(clone_dir),
                    ]
                )

                # Build as non-root (makepkg cannot run as root)
                cwd = os.getcwd()
                os.chdir(clone_dir)
                try:
                    # We assume the user running the script has sudo rights and isn't root
                    subprocess.run(["makepkg", "-si", "--noconfirm"], check=True)
                finally:
                    os.chdir(cwd)
        except Exception as e:
            logger.error(f"Failed to setup yay: {e}")
            console.print("[red]Failed to install yay. AUR steps may fail.[/red]")

    def install(self, packages: List[str], method: str = "pacman"):
        if not packages:
            return

        unique_pkgs = sorted(list(set(packages)))
        to_install = []

        # Checking logic
        if method == "flatpak":
            res = Utils.run_command(["flatpak", "list"], quiet=True)
            for pkg in unique_pkgs:
                if pkg not in res.stdout:
                    to_install.append(pkg)
        else:
            # For pacman/aur, we can batch check
            # But simple `pacman -Qi` loop is safer for mixed lists
            for pkg in unique_pkgs:
                res = Utils.run_command(["pacman", "-Qi", pkg], quiet=True, check=False)
                if res.returncode != 0:
                    to_install.append(pkg)

        if not to_install:
            console.print(f"[green]All {method} packages already installed.[/green]")
            return

        console.print(
            f"[cyan]Installing {len(to_install)} packages via {method}...[/cyan]"
        )

        if method == "pacman":
            cmd = ["pacman", "-S", "--noconfirm", "--needed"] + to_install
            res = Utils.run_command(cmd, sudo=True, check=False, quiet=False)
        elif method == "aur":
            cmd = ["yay", "-S", "--noconfirm", "--needed"] + to_install
            res = Utils.run_command(cmd, sudo=False, check=False, quiet=False)
        elif method == "flatpak":
            # Flatpak install often needs --noninteractive
            for pkg in to_install:
                cmd = ["flatpak", "install", "-y", "--noninteractive", "flathub", pkg]
                res = Utils.run_command(cmd, sudo=True, check=False, quiet=False)
                # Flatpak returns 0 even if nothing installed sometimes, but we proceed

        if method != "flatpak" and res.returncode == 0:
            console.print(
                f"[green]Successfully installed packages via {method}[/green]"
            )
        elif method == "flatpak":
            console.print(f"[green]Finished Flatpak operations[/green]")
        else:
            console.print(f"[red]Failed to install some packages via {method}[/red]")
            self.failed_packages.extend(to_install)


class ArchInstaller:
    def __init__(self):
        self.probe = SystemProbe()
        self.config = ConfigLoader(CONFIG_DIR / "programs.yaml")
        self.pm = PackageManager()
        self.mode = "default"

    def show_banner(self):
        console.clear()
        banner = """
   _             _     ___           _        _ _
  / \   _ __ ___| |__ |_ _|_ __  ___| |_ __ _| | |
 / _ \ | '__/ __| '_ \ | || '_ \/ __| __/ _` | | |
/ ___ \| | | (__| | | || || | | \__ \ || (_| | | |
/_/   \_\_|  \___|_| |_|___|_| |_|___/\__\__,_|_|_|
                                Python Edition v1.0
        """
        console.print(
            Panel(banner, style="bold blue", subtitle="Created by George Andromidas")
        )

        table = Table(show_header=False, box=None)
        table.add_row("CPU", f"[green]{self.probe.cpu_vendor.upper()}[/green]")
        table.add_row("GPU", f"[green]{self.probe.gpu_vendor.upper()}[/green]")
        table.add_row("RAM", f"[green]{self.probe.ram_gb} GB[/green]")
        table.add_row(
            "System",
            "[green]Laptop[/green]"
            if self.probe.is_laptop
            else "[green]Desktop[/green]",
        )
        table.add_row("Bootloader", f"[green]{self.probe.bootloader.upper()}[/green]")
        table.add_row("Filesystem", f"[green]{self.probe.filesystem.upper()}[/green]")
        console.print(table)
        print()

    def select_mode(self):
        console.print("[bold cyan]Select Installation Mode:[/bold cyan]")
        console.print("1. [green]Standard[/green] (Recommended)")
        console.print("2. [yellow]Minimal[/yellow] (Core tools only)")
        console.print("3. [magenta]Server[/magenta] (Headless, Docker)")

        choice = Prompt.ask("Choose", choices=["1", "2", "3"], default="1")
        if choice == "2":
            self.mode = "minimal"
        elif choice == "3":
            self.mode = "server"
        else:
            self.mode = "default"
        console.print(f"[bold]Selected Mode: {self.mode}[/bold]")

    def step_system_prep(self):
        console.rule("[bold blue]Step 1: System Preparation")
        with console.status("[bold green]Optimizing Pacman..."):
            # Pacman Config
            conf = Path("/etc/pacman.conf")
            if conf.exists():
                Utils.sed_replace(conf, "^#ParallelDownloads", "ParallelDownloads")
                Utils.sed_replace(conf, "^#Color", "Color")
                # ILoveCandy
                try:
                    txt = conf.read_text()
                    if "ILoveCandy" not in txt:
                        Utils.sed_replace(conf, "^Color", "Color\\nILoveCandy")
                except:
                    pass
                # Multilib
                try:
                    txt = conf.read_text()
                    if "[multilib]" not in txt:
                        Utils.append_to_file(
                            conf, "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n"
                        )
                except:
                    pass

        # Smart Locale
        self._smart_locale()

        # Update
        console.print("[cyan]Updating system...[/cyan]")
        Utils.run_command(["pacman", "-Syu", "--noconfirm"], sudo=True)

        # Install Essentials
        self.pm.install(
            ["base-devel", "git", "speedtest-cli", "wget", "curl", "unzip"], "pacman"
        )

    def _smart_locale(self):
        console.print("[cyan]Detecting location for locale setup...[/cyan]")

        # Default fallback
        if Path("/etc/locale.gen").exists():
            Utils.sed_replace(Path("/etc/locale.gen"), "^#en_US.UTF-8", "en_US.UTF-8")

        country = None
        try:
            with urllib.request.urlopen(
                "https://ifconfig.co/country-iso", timeout=5
            ) as url:
                country = url.read().decode().strip()
        except:
            try:
                # Fallback API
                with urllib.request.urlopen(
                    "http://ip-api.com/line/?fields=countryCode", timeout=5
                ) as url:
                    country = url.read().decode().strip()
            except:
                pass

        if country and len(country) == 2:
            console.print(f"Detected Country: [green]{country}[/green]")
            try:
                # Naive match: look for _<CODE>.UTF-8
                with open("/etc/locale.gen", "r") as f:
                    lines = f.readlines()

                target_locale = None
                for line in lines:
                    if line.strip().startswith("#") and line.endswith(
                        f"_{country}.UTF-8\n"
                    ):
                        target_locale = line.strip().lstrip("#")
                        break

                if target_locale:
                    console.print(f"Enabling locale: [green]{target_locale}[/green]")
                    Utils.sed_replace(
                        Path("/etc/locale.gen"), f"^#{target_locale}", target_locale
                    )
            except Exception as e:
                logger.error(f"Locale setup failed: {e}")

        Utils.run_command(["locale-gen"], sudo=True)

    def step_shell_setup(self):
        console.rule("[bold blue]Step 2: Shell Setup")

        # ZSH & Plugins
        self.pm.install(
            [
                "zsh",
                "zsh-autosuggestions",
                "zsh-syntax-highlighting",
                "starship",
                "fastfetch",
                "eza",
                "fzf",
                "zoxide",
            ],
            "pacman",
        )

        # Oh-My-Zsh
        omz_dir = Path.home() / ".oh-my-zsh"
        if not omz_dir.exists():
            console.print("Installing Oh-My-Zsh...")
            Utils.run_command(
                [
                    "sh",
                    "-c",
                    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)",
                ],
                quiet=False,
            )

        # Configs
        for cfg in [".zshrc", "starship.toml"]:
            src = CONFIG_DIR / cfg
            if src.exists():
                if cfg == "starship.toml":
                    dest_dir = Path.home() / ".config"
                    dest_dir.mkdir(exist_ok=True)
                    shutil.copy2(src, dest_dir / cfg)
                else:
                    shutil.copy2(src, Path.home() / cfg)

        # Default Shell
        if "zsh" not in os.environ["SHELL"]:
            console.print("[cyan]Changing default shell to ZSH...[/cyan]")
            Utils.run_command(
                ["chsh", "-s", "/usr/bin/zsh", os.environ["USER"]], sudo=True
            )

        # DE specific config
        if "GNOME" in self.probe.desktop_env:
            self._gnome_tweaks()
        elif "KDE" in self.probe.desktop_env:
            self._kde_tweaks()

    def _gnome_tweaks(self):
        if shutil.which("gsettings"):
            console.print("[cyan]Applying GNOME settings...[/cyan]")
            # Dark Theme
            Utils.run_command(
                [
                    "gsettings",
                    "set",
                    "org.gnome.desktop.interface",
                    "color-scheme",
                    "'prefer-dark'",
                ]
            )
            # Min/Max buttons
            Utils.run_command(
                [
                    "gsettings",
                    "set",
                    "org.gnome.desktop.wm.preferences",
                    "button-layout",
                    "'appmenu:minimize,maximize,close'",
                ]
            )

    def _kde_tweaks(self):
        src = CONFIG_DIR / "kglobalshortcutsrc"
        if src.exists():
            dest = Path.home() / ".config" / "kglobalshortcutsrc"
            dest.parent.mkdir(exist_ok=True)
            shutil.copy2(src, dest)
            console.print("[green]Applied KDE shortcuts[/green]")

    def step_plymouth(self):
        if self.mode == "server":
            return
        console.rule("[bold blue]Step 3: Plymouth Boot Screen")

        self.pm.install(["plymouth"], "pacman")

        # Configure hooks
        mkinit = Path("/etc/mkinitcpio.conf")
        if mkinit.exists():
            content = mkinit.read_text()
            if "plymouth" not in content:
                # Smart detection: systemd vs udev
                if "systemd" in content and "udev" not in content:
                    Utils.sed_replace(mkinit, "systemd", "systemd sd-plymouth")
                elif "udev" in content:
                    Utils.sed_replace(mkinit, "udev", "udev plymouth")
                else:
                    Utils.sed_replace(mkinit, "filesystems", "plymouth filesystems")

                console.print("[cyan]Rebuilding initramfs...[/cyan]")
                Utils.run_command(["mkinitcpio", "-P"], sudo=True)

        # Theme
        if shutil.which("plymouth-set-default-theme"):
            Utils.run_command(["plymouth-set-default-theme", "-R", "bgrt"], sudo=True)

    def step_packages(self):
        console.rule("[bold blue]Step 4: Installing Packages")

        # Ensure AUR
        if self.mode != "server":
            self.pm.ensure_yay()

        # Pacman
        pkgs = self.config.get_packages(self.mode, "pacman")
        self.pm.install(pkgs, "pacman")

        # Essential
        pkgs = self.config.get_packages(self.mode, "essential")
        self.pm.install(pkgs, "pacman")

        if self.mode != "server":
            # AUR
            pkgs = self.config.get_packages(self.mode, "aur")
            self.pm.install(pkgs, "aur")

            # Flatpak
            if shutil.which("flatpak"):
                # Add remote
                Utils.run_command(
                    [
                        "flatpak",
                        "remote-add",
                        "--if-not-exists",
                        "flathub",
                        "https://dl.flathub.org/repo/flathub.flatpakrepo",
                    ],
                    sudo=True,
                )

                # Desktop specific flatpaks
                de_key = "generic"
                if "KDE" in self.probe.desktop_env:
                    de_key = "kde"
                if "GNOME" in self.probe.desktop_env:
                    de_key = "gnome"
                if "COSMIC" in self.probe.desktop_env:
                    de_key = "cosmic"

                pkgs = self.config.get_packages(self.mode, "flatpak", de_key)
                self.pm.install(pkgs, "flatpak")

            # DE Specific Pacman
            if "KDE" in self.probe.desktop_env:
                self.pm.install(
                    self.config.get_packages(self.mode, "desktop_environments", "kde"),
                    "pacman",
                )
            elif "GNOME" in self.probe.desktop_env:
                self.pm.install(
                    self.config.get_packages(
                        self.mode, "desktop_environments", "gnome"
                    ),
                    "pacman",
                )

    def step_gaming(self):
        if self.mode == "server":
            return
        console.rule("[bold blue]Step 5: Gaming Mode")

        if Confirm.ask("Install Gaming optimizations? (Steam, Lutris, Gamemode)"):
            # Load gaming config if exists, else manual list
            gaming_yaml = CONFIG_DIR / "gaming_mode.yaml"
            if gaming_yaml.exists():
                gaming_loader = ConfigLoader(gaming_yaml)
                self.pm.install(
                    gaming_loader.get_packages("default", "pacman", "packages"),
                    "pacman",
                )
                self.pm.install(
                    gaming_loader.get_packages("default", "flatpak", "apps"), "flatpak"
                )
            else:
                self.pm.install(
                    ["steam", "gamemode", "mangohud", "wine", "lutris"], "pacman"
                )

            # Enable gamemode
            Utils.run_command(
                ["systemctl", "--user", "enable", "--now", "gamemoded"], check=False
            )

            # Copy MangoHud config
            src = CONFIG_DIR / "MangoHud.conf"
            dest = Path.home() / ".config" / "MangoHud" / "MangoHud.conf"
            if src.exists():
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dest)

    def step_bootloader(self):
        console.rule("[bold blue]Step 6: Bootloader Configuration")

        # Silent Boot parameters
        params = "quiet splash loglevel=3 systemd.show_status=auto rd.udev.log_level=3"

        if self.probe.bootloader == "grub":
            grub_cfg = Path("/etc/default/grub")
            if grub_cfg.exists():
                Utils.sed_replace(grub_cfg, "^GRUB_TIMEOUT=.*", "GRUB_TIMEOUT=3")
                # Add params to CMDLINE_DEFAULT
                # Complex regex replacement simplified
                current = grub_cfg.read_text()
                if "quiet" not in current:
                    Utils.sed_replace(
                        grub_cfg,
                        'GRUB_CMDLINE_LINUX_DEFAULT="',
                        f'GRUB_CMDLINE_LINUX_DEFAULT="{params} ',
                    )
                Utils.run_command(
                    ["grub-mkconfig", "-o", "/boot/grub/grub.cfg"], sudo=True
                )

        elif self.probe.bootloader == "systemd-boot":
            entries = list(Path("/boot/loader/entries").glob("*.conf"))
            for entry in entries:
                if "fallback" not in entry.name:
                    content = entry.read_text()
                    if "quiet" not in content:
                        Utils.append_to_file(entry, f"options {params}")

    def step_security(self):
        console.rule("[bold blue]Step 7: Security (Fail2ban & Firewall)")

        # Firewalld
        self.pm.install(["firewalld", "fail2ban"], "pacman")
        Utils.run_command(["systemctl", "enable", "--now", "firewalld"], sudo=True)

        # Fail2ban
        jail_local = Path("/etc/fail2ban/jail.local")
        if not jail_local.exists():
            shutil.copy2(Path("/etc/fail2ban/jail.conf"), jail_local)
            Utils.sed_replace(jail_local, "backend = auto", "backend = systemd")
            Utils.run_command(["systemctl", "enable", "--now", "fail2ban"], sudo=True)

    def step_hardware_tuning(self):
        console.rule("[bold blue]Step 8: Hardware Optimization")

        # GPU
        if self.probe.gpu_vendor == "nvidia":
            console.print("[yellow]NVIDIA GPU detected.[/yellow]")
            # Simplified Logic: Check card generation or just install standard
            # For robustness in v1, we assume modern/standard
            self.pm.install(
                [
                    "nvidia-dkms",
                    "nvidia-utils",
                    "lib32-nvidia-utils",
                    "nvidia-settings",
                ],
                "pacman",
            )
        elif self.probe.gpu_vendor == "amd":
            self.pm.install(
                ["mesa", "xf86-video-amdgpu", "vulkan-radeon", "lib32-vulkan-radeon"],
                "pacman",
            )
        elif self.probe.gpu_vendor == "intel":
            self.pm.install(["mesa", "vulkan-intel", "intel-media-driver"], "pacman")

        # Laptop
        if self.probe.is_laptop:
            console.print("[cyan]Laptop detected. Installing optimizations...[/cyan]")
            self.pm.install(["power-profiles-daemon", "thermald"], "pacman")
            Utils.run_command(
                ["systemctl", "enable", "--now", "power-profiles-daemon"],
                sudo=True,
                check=False,
            )
            if self.probe.cpu_vendor == "intel":
                Utils.run_command(
                    ["systemctl", "enable", "--now", "thermald"], sudo=True, check=False
                )

            # Touchpad gestures
            if self.mode != "server" and shutil.which("yay"):
                self.pm.install(["libinput-gestures", "xdotool", "wmctrl"], "aur")
                # User needs to add themselves to input group
                Utils.run_command(
                    ["usermod", "-aG", "input", os.environ["USER"]], sudo=True
                )

        # SSD Trim
        if shutil.which("fstrim"):
            Utils.run_command(
                ["systemctl", "enable", "--now", "fstrim.timer"], sudo=True
            )

    def step_maintenance(self):
        console.rule("[bold blue]Step 9: Maintenance & Btrfs")

        # Cache cleaning
        Utils.run_command(["pacman", "-Sc", "--noconfirm"], sudo=True)

        # Btrfs Snapshots
        if self.probe.filesystem == "btrfs":
            console.print("[green]Btrfs detected. Configuring Snapper...[/green]")
            self.pm.install(
                ["snapper", "snap-pac", "btrfs-assistant", "grub-btrfs"], "pacman"
            )

            # Init config if missing
            if not Path("/etc/snapper/configs/root").exists():
                Utils.run_command(
                    ["snapper", "-c", "root", "create-config", "/"], sudo=True
                )
                # Tweak config retention
                cfg = Path("/etc/snapper/configs/root")
                Utils.sed_replace(
                    cfg, "TIMELINE_limit_HOURLY=.*", 'TIMELINE_LIMIT_HOURLY="5"'
                )
                Utils.sed_replace(
                    cfg, "TIMELINE_LIMIT_DAILY=.*", 'TIMELINE_LIMIT_DAILY="7"'
                )

            # Enable timers
            Utils.run_command(
                ["systemctl", "enable", "--now", "snapper-timeline.timer"], sudo=True
            )
            Utils.run_command(
                ["systemctl", "enable", "--now", "snapper-cleanup.timer"], sudo=True
            )

            if self.probe.bootloader == "grub":
                Utils.run_command(
                    ["systemctl", "enable", "--now", "grub-btrfsd"], sudo=True
                )

    def run(self):
        if os.geteuid() == 0:
            console.print(
                "[red]Do NOT run as root. Run as user with sudo privileges.[/red]"
            )
            sys.exit(1)

        self.show_banner()

        if not Utils.check_internet():
            console.print("[red]No internet connection![/red]")
            sys.exit(1)

        self.select_mode()

        if not Confirm.ask("Start installation?"):
            sys.exit(0)

        # Installation Flow
        try:
            self.step_system_prep()
            self.step_shell_setup()
            self.step_plymouth()
            self.step_packages()
            self.step_gaming()
            self.step_bootloader()
            self.step_security()
            self.step_hardware_tuning()
            self.step_maintenance()

            console.print(
                Panel("Installation Complete! Please reboot.", style="bold green")
            )
        except Exception as e:
            logger.exception("Installation crashed")
            console.print(Panel(f"Critical Error: {e}", style="bold red"))


if __name__ == "__main__":
    try:
        installer = ArchInstaller()
        installer.run()
    except KeyboardInterrupt:
        print("\nInterrupted.")
        sys.exit(1)
