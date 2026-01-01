# FAQ

Frequently asked questions about LinuxInstaller.

## 📋 General Questions

### What is LinuxInstaller?

LinuxInstaller is a comprehensive, cross-distribution post-installation script that transforms your fresh Linux installation into a fully configured, optimized development environment with beautiful terminal aesthetics.

### Which distributions are supported?

- **Arch Linux** (with AUR support)
- **Fedora** (with COPR support)
- **Debian** & **Ubuntu** (with Snap support)

### What does LinuxInstaller install?

- **Security**: UFW firewall, fail2ban, SSH hardening
- **Performance**: CPU governor tuning, ZRAM, filesystem optimization
- **Shell**: Zsh with autosuggestions, Starship prompt, Fastfetch
- **Development**: Git, build tools, package managers
- **Desktop**: KDE Plasma or GNOME customizations (optional)
- **Gaming**: Steam, Wine, GPU drivers (optional)

## 🚀 Installation Questions

### How do I install LinuxInstaller?

**One-line installation:**
```bash
wget -qO- https://raw.githubusercontent.com/GAndromidas/linuxinstaller/main/install.sh | bash
```

**Manual installation:**
```bash
git clone https://github.com/GAndromidas/linuxinstaller.git
cd linuxinstaller
chmod +x install.sh
sudo ./install.sh
```

### What are the installation modes?

| Mode | Description | Use Case |
|------|-------------|----------|
| **Standard** | Complete setup with all packages | Full desktop development |
| **Minimal** | Essential tools only | Lightweight systems, VMs |
| **Server** | Headless server configuration | Production servers |

### Can I preview what will be installed?

Yes! Use the dry-run mode:
```bash
sudo ./install.sh --dry-run --verbose
```

This shows exactly what would be installed without making any changes.

### How long does installation take?

- **Minimal Mode**: ~5 minutes
- **Standard Mode**: ~12 minutes
- **Gaming Suite**: ~8 minutes additional

Times vary based on internet speed and system performance.

## 🔧 Configuration Questions

### Can I customize what gets installed?

Yes! You can modify the package lists in the script files:

- `scripts/arch_config.sh` - Arch Linux packages
- `scripts/fedora_config.sh` - Fedora packages
- `scripts/debian_config.sh` - Debian/Ubuntu packages

### How do I change the shell configuration?

Modify the configuration files:
- `~/.zshrc` - Zsh shell settings
- `~/.config/starship.toml` - Starship prompt
- `~/.config/fastfetch/config.jsonc` - System information display

### Can I use LinuxInstaller on an existing system?

Yes, but be aware:
- The script modifies system files directly
- No automatic backups are created
- Review changes before running on production systems

## 🎨 UI and Display Questions

### Why does the interface look different?

The script uses **gum** for beautiful terminal UI. If gum isn't available, it falls back to text-based menus.

**Install gum for full experience:**
```bash
# Arch Linux
sudo pacman -S gum

# Ubuntu/Debian
sudo apt install gum

# Fedora
sudo dnf install gum
```

### How do I change the color scheme?

Modify the color variables in `scripts/common.sh`:

```bash
# Gum color scheme
GUM_PRIMARY_FG=cyan      # Primary color
GUM_BODY_FG=87          # Body text color
GUM_SUCCESS_FG=48       # Success messages
GUM_ERROR_FG=196        # Error messages
GUM_WARNING_FG=226      # Warning messages
```

## 🔒 Security Questions

### Is LinuxInstaller secure?

LinuxInstaller implements multiple security measures:

- **Input validation** for all package names and user inputs
- **No hardcoded secrets** or credentials
- **Secure file permissions** (no world-writable files)
- **Safe command execution** without shell injection vulnerabilities

### What security features does it enable?

- **UFW Firewall**: Configured with essential rules
- **Fail2ban**: SSH brute-force protection (3 attempts → 1 hour ban)
- **SSH Hardening**: Secure configuration with key-based authentication
- **AppArmor/SELinux**: Distribution-appropriate security framework

### Can I customize security settings?

Yes! Modify the security configurations in `scripts/security_config.sh` to adjust firewall rules, fail2ban settings, and SSH configurations.

## ⚡ Performance Questions

### What performance optimizations does it apply?

- **CPU Governor**: Sets CPU to performance mode for responsive desktop experience
- **ZRAM**: Compressed swap for systems with limited RAM
- **Filesystem**: Btrfs snapshots, SSD TRIM, optimized mount options
- **Network**: TCP optimizations and buffer tuning

### Can I adjust performance settings?

Yes! Modify settings in `scripts/performance_config.sh`:

```bash
# CPU governor (performance/balanced/powersave)
DEFAULT_GOVERNOR="performance"

# ZRAM size as percentage of RAM
ZRAM_SIZE_PERCENT=50

# Filesystem mount options
MOUNT_OPTIONS="noatime,commit=60"
```

## 🖥️ Desktop Environment Questions

### Which desktop environments are supported?

- **KDE Plasma**: Global shortcuts, theme optimization, KDE Connect
- **GNOME**: Extension installation, theme customization, workspace configuration

### How do I change desktop environment settings?

**KDE Plasma:**
- Global shortcuts: `~/.config/kglobalshortcutsrc`
- Theme settings: System Settings → Appearance

**GNOME:**
- Extensions: GNOME Extensions app or command line
- Themes: GNOME Tweaks or gsettings commands

### What if I use a different desktop environment?

LinuxInstaller focuses on KDE Plasma and GNOME but provides universal shell configurations that work across all desktop environments.

## 🎮 Gaming Questions

### Does LinuxInstaller include gaming support?

Yes! The gaming suite includes:
- **Steam** installation and configuration
- **Wine** for Windows game compatibility
- **GPU drivers** for AMD, Intel, and NVIDIA (NVIDIA requires manual installation)
- **Performance tools**: MangoHud for monitoring, GameMode for optimization

### How do I enable gaming packages?

During installation, choose **Standard** or **Minimal** mode and answer "Yes" when prompted about the gaming suite.

### What about NVIDIA GPUs?

NVIDIA drivers require manual installation due to licensing. After running LinuxInstaller:

```bash
# Arch Linux
sudo pacman -S nvidia nvidia-utils

# Ubuntu/Debian
sudo apt install nvidia-driver

# Fedora
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda

# Reboot required
sudo reboot
```

## 🐚 Shell Questions

### What shell configurations does it install?

- **Zsh**: Modern shell with autosuggestions and syntax highlighting
- **Starship**: Beautiful, fast, customizable prompt
- **Fastfetch**: System information display tool
- **Zsh plugins**: Autosuggestions and syntax highlighting

### How do I change the default shell?

After installation:
```bash
chsh -s $(which zsh) $USER
```

Then logout and login again, or run:
```bash
exec zsh
```

### Can I keep using Bash?

Yes! LinuxInstaller installs Zsh alongside your existing shell. You can switch between them anytime.

## 🔧 Technical Questions

### Can I run LinuxInstaller multiple times?

Yes, but be cautious:
- The script is designed to be idempotent (safe to run multiple times)
- Some changes may be applied repeatedly
- Use `--dry-run` first to see what would change

### What if installation fails partway through?

The script includes error handling, but if it fails:
1. Check the error messages
2. Fix the underlying issue (network, packages, etc.)
3. Run the script again - it will attempt to continue where it left off

### Can I uninstall LinuxInstaller changes?

Partial uninstallation is possible but not fully automated:
- Remove installed packages manually
- Restore original configuration files (if you backed them up)
- Reset firewall and security settings
- Change shell back to original

### Where are configuration files stored?

- **User configs**: `~/.zshrc`, `~/.config/starship.toml`, `~/.config/fastfetch/`
- **System configs**: `/etc/fail2ban/`, `/etc/ssh/`, `/etc/ufw/`
- **Scripts**: `/usr/local/bin/` (for maintenance scripts)

## 🆘 Troubleshooting Questions

### The script says "No internet connection"

Check your network:
```bash
ping -c 3 8.8.8.8
ping -c 3 google.com
```

If behind a proxy:
```bash
export http_proxy="http://proxy.company.com:8080"
export https_proxy="http://proxy.company.com:8080"
```

### Package installation fails

Update package databases:
```bash
# Arch Linux
sudo pacman -Syy

# Ubuntu/Debian
sudo apt update

# Fedora
sudo dnf check-update
```

### GPU drivers not working

**AMD/Intel:** Should work automatically after installation
**NVIDIA:** Requires manual installation (see gaming section above)

### Services not starting

Check service status:
```bash
sudo systemctl status ufw
sudo systemctl status fail2ban
sudo systemctl status sshd
```

Enable and start if needed:
```bash
sudo systemctl enable --now service_name
```

## 🤝 Contributing Questions

### How can I contribute?

Great! Ways to contribute:
- **Code**: Fix bugs, add features, improve performance
- **Documentation**: Update wiki, improve guides, translate
- **Testing**: Test on different distributions, report issues
- **Feedback**: Share your experience and suggestions

See the [[Development Guide|Development-Guide]] for detailed contribution instructions.

### I found a bug, what should I do?

1. Check if it's already reported in [GitHub Issues](https://github.com/GAndromidas/linuxinstaller/issues)
2. If not, create a new issue with:
   - Your distribution and version
   - Exact error messages
   - Steps to reproduce
   - Expected vs actual behavior

### Can I suggest new features?

Absolutely! Open a [GitHub Discussion](https://github.com/GAndromidas/linuxinstaller/discussions) or create a feature request issue.

## 📞 Support Questions

### Where can I get help?

- **📖 Documentation**: This wiki and README
- **🐛 Bug Reports**: [GitHub Issues](https://github.com/GAndromidas/linuxinstaller/issues)
- **💬 General Discussion**: [GitHub Discussions](https://github.com/GAndromidas/linuxinstaller/discussions)
- **📧 Direct Help**: Create a new discussion thread

### How do I create a good bug report?

Include:
1. **System info**: Distribution, kernel version, hardware
2. **Steps to reproduce**: Exact commands and options used
3. **Error output**: Full error messages (use `--verbose`)
4. **Expected behavior**: What you expected to happen
5. **Actual behavior**: What actually happened

### Is there a community forum?

Use [GitHub Discussions](https://github.com/GAndromidas/linuxinstaller/discussions) for:
- General questions
- Feature requests
- Show and tell
- Development discussions

## 📈 Future Questions

### Will more distributions be supported?

Possibly! The modular design makes it relatively easy to add new distributions. Popular requests include:
- openSUSE
- Gentoo
- NixOS
- Linux Mint (beyond Ubuntu base)

### Are there plans for a GUI version?

Not currently planned, but the terminal UI with gum provides an excellent user experience. The focus remains on the terminal-based installation for maximum compatibility and minimal dependencies.

### Can I use LinuxInstaller in automated scripts?

Yes! Use the non-interactive modes:
```bash
# Fully automated installation
export INSTALL_MODE="standard"
export INSTALL_GAMING=true
sudo ./install.sh
```

For CI/CD pipelines, use the `--dry-run` mode first to validate your configuration.

---

**Still have questions?** Check the [[Troubleshooting|Troubleshooting]] guide or create a [new discussion](https://github.com/GAndromidas/linuxinstaller/discussions)! 🚀</content>
<parameter name="filePath">linuxinstaller/wiki/FAQ.md