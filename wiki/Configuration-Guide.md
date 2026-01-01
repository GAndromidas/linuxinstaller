# Configuration Guide

This guide explains how to customize LinuxInstaller to fit your specific needs and preferences.

## 🎯 Configuration Overview

LinuxInstaller is designed to be highly configurable while providing sensible defaults. You can customize:

- **Package Selection**: Choose which packages to install
- **Installation Modes**: Modify what each mode includes
- **Desktop Environment**: Configure KDE Plasma or GNOME settings
- **Security Settings**: Adjust firewall and SSH configurations
- **Performance Tuning**: Customize optimization settings
- **Shell Configuration**: Personalize Zsh, Starship, and Fastfetch

## 📁 Configuration Files Structure

```
linuxinstaller/
├── install.sh              # Main script (customizable)
├── scripts/               # Modular components
│   ├── common.sh          # UI and logging configuration
│   ├── distro_check.sh    # Distribution detection
│   ├── arch_config.sh     # Arch Linux specific config
│   ├── fedora_config.sh   # Fedora specific config
│   ├── debian_config.sh   # Debian/Ubuntu specific config
│   └── *.sh               # Other configuration modules
└── configs/               # User configuration files
    ├── arch/ .zshrc starship.toml fastfetch.jsonc
    ├── fedora/ ...
    └── */*.toml           # Distribution-specific configs
```

## 🔧 Customizing Package Lists

### Adding Custom Packages

Edit the distribution-specific configuration files:

**For Arch Linux** (`scripts/arch_config.sh`):
```bash
# Add to ARCH_NATIVE_STANDARD array
ARCH_NATIVE_STANDARD+=(
    "your-package-name"
    "another-package"
)
```

**For Fedora** (`scripts/fedora_config.sh`):
```bash
# Add to FEDORA_NATIVE_STANDARD array
FEDORA_NATIVE_STANDARD+=(
    "your-package-name"
    "another-package"
)
```

### Removing Unwanted Packages

Comment out or remove packages from the arrays:

```bash
ARCH_NATIVE_STANDARD=(
    "base-devel"
    "bc"
    # "bluez-utils"    # Commented out - not needed
    "cronie"
    # Add your custom packages here
)
```

### Creating Custom Groups

You can create custom package groups by modifying the `distro_get_packages()` function:

```bash
case "$section" in
    "custom")
        case "$type" in
            native) printf "%s\n" "${CUSTOM_PACKAGES[@]}" ;;
            *) return 0 ;;
        esac
        ;;
```

## 🎨 Customizing the UI

### Color Scheme

Edit `scripts/common.sh` to change the color scheme:

```bash
# GUM color scheme (refactored for cyan theme)
GUM_PRIMARY_FG=cyan      # Primary color for headings
GUM_BODY_FG=87          # Light cyan for body text
GUM_BORDER_FG=cyan      # Border color
GUM_SUCCESS_FG=48       # Success message color
GUM_ERROR_FG=196        # Error message color
GUM_WARNING_FG=226      # Warning message color
```

### Menu Options

Modify the menu in `install.sh`:

```bash
choice=$(gum choose \
    "Standard - Complete setup with all recommended packages" \
    "Minimal - Essential tools only for lightweight installations" \
    "Custom - Your custom configuration" \  # Add custom option
    "Server - Headless server configuration" \
    "Exit" \
    --cursor.foreground "$GUM_PRIMARY_FG" --cursor "→" \
    --selected.foreground "$GUM_SUCCESS_FG")
```

## 🖥️ Desktop Environment Configuration

### KDE Plasma Customization

**Keyboard Shortcuts** (`configs/arch/kglobalshortcutsrc`):
```ini
[Plasma]
Meta+Q=close
Meta+Return=run_command,konsole
```

**Panel Configuration**: Modify KDE settings after installation:
```bash
# Open KDE System Settings
systemsettings

# Or use command line
kcmshell5 kcm_kdeglobals
```

### GNOME Customization

**Extensions**: LinuxInstaller installs popular GNOME extensions. To add more:

```bash
# Install additional extensions
sudo dnf install gnome-shell-extension-*  # Fedora
sudo apt install gnome-shell-extension-*  # Ubuntu

# Enable extensions
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
```

## 🔒 Security Configuration

### Firewall Rules

Customize UFW rules by modifying the security configuration:

**Custom Rules** (`scripts/security_config.sh`):
```bash
# Add custom firewall rules
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 22/tcp    # SSH (already included)
```

### SSH Hardening

Modify SSH configuration in the security module:

```bash
# Additional SSH hardening
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
```

### Fail2ban Configuration

Customize fail2ban settings:

```bash
# Modify jail settings
cat >> /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF
```

## ⚡ Performance Tuning

### CPU Governor Configuration

Modify CPU governor settings in `scripts/performance_config.sh`:

```bash
# Change default governor (performance/balanced/powersave)
DEFAULT_GOVERNOR="performance"
```

### ZRAM Configuration

Adjust ZRAM settings:

```bash
# ZRAM size (percentage of RAM)
ZRAM_SIZE_PERCENT=50
```

### Filesystem Optimization

Customize filesystem mount options:

```bash
# Add custom mount options
MOUNT_OPTIONS="noatime,commit=60"
```

## 🐚 Shell Configuration

### Zsh Customization

Modify `configs/*/zshrc` for your shell preferences:

```bash
# Add custom aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Custom functions
function mkcd() {
    mkdir -p "$1" && cd "$1"
}
```

### Starship Prompt

Customize the prompt in `configs/*/starship.toml`:

```toml
# Add custom modules
[custom.git]
command = "git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ''"
when = "git rev-parse --git-dir 2>/dev/null"
format = "on [$output]($style) "

# Change colors
[username]
style_user = "bright-cyan"
style_root = "bright-red"
```

### Fastfetch Configuration

Modify system information display in `configs/*/config.jsonc`:

```jsonc
{
  "display": {
    "separator": " → ",
    "color": {
      "keys": "cyan",
      "title": "light_blue"
    }
  },
  "modules": [
    "title",
    "separator",
    "os",
    "kernel",
    "uptime",
    "packages",
    "shell",
    "terminal",
    "cpu",
    "gpu",
    "memory",
    "disk",
    "break",
    "colors"
  ]
}
```

## 🎮 Gaming Configuration

### Custom GPU Drivers

For custom GPU driver installation, modify the gaming module:

```bash
# Add support for new GPU vendors
detect_custom_gpu() {
    # Custom GPU detection logic
    if lspci | grep -i "custom gpu"; then
        install_pkg "custom-driver"
    fi
}
```

### Steam Configuration

Customize Steam settings:

```bash
# Steam launch options for games
# Add to game's properties: gamemoded %command%
# Or: mangohud %command%
```

## 🔧 Advanced Customization

### Custom Installation Modes

Create new installation modes by modifying the main script:

```bash
# Add custom mode
"Developer - Development tools only" \
"Designer - Creative applications" \
```

Handle the new mode:

```bash
case "$choice" in
    "Developer - Development tools only")
        export INSTALL_MODE="developer"
        export CUSTOM_PACKAGES=("vscode" "docker" "nodejs" "python")
        ;;
```

### Distribution-Specific Overrides

Override settings for specific distributions:

```bash
case "$DISTRO_ID" in
    "ubuntu")
        # Ubuntu-specific customizations
        export APT_CONF="/etc/apt/apt.conf.d/99custom"
        ;;
    "fedora")
        # Fedora-specific customizations
        export DNF_CONF="/etc/dnf/dnf.conf"
        ;;
esac
```

## 📋 Configuration Validation

### Testing Changes

```bash
# Test configuration with dry run
sudo ./install.sh --dry-run --verbose

# Check for syntax errors
bash -n install.sh
bash -n scripts/*.sh

# Validate JSON/TOML files
python3 -m json.tool configs/*/config.jsonc
```

### Backup Important Files

```bash
# Backup before customization
cp ~/.zshrc ~/.zshrc.backup
cp ~/.config/starship.toml ~/.config/starship.toml.backup
cp /etc/fail2ban/jail.local /etc/fail2ban/jail.local.backup
```

## 🆘 Common Customization Issues

### Configuration Not Applied
- Check file permissions: `ls -la ~/.zshrc`
- Verify syntax: `zsh -n ~/.zshrc`
- Restart shell: `exec zsh`

### Package Installation Fails
- Check package name spelling
- Verify package exists: `pacman -Si package_name` (Arch)
- Update package database: `sudo pacman -Syy` (Arch)

### UI Changes Not Visible
- Restart terminal emulator
- Check gum installation: `which gum`
- Verify color support: `echo $TERM`

## 📞 Getting Help

- **Configuration Examples**: Check the [[FAQ|FAQ]] for common customizations
- **Community Help**: [GitHub Discussions](https://github.com/GAndromidas/linuxinstaller/discussions)
- **Bug Reports**: [GitHub Issues](https://github.com/GAndromidas/linuxinstaller/issues)

## 🎯 Best Practices

1. **Test Changes**: Always use `--dry-run` first
2. **Backup Files**: Save originals before modification
3. **Document Changes**: Comment your customizations
4. **Version Control**: Track changes in git
5. **Share Improvements**: Consider contributing back to the project

Remember: LinuxInstaller is designed to be flexible. Don't hesitate to experiment and customize it to perfectly fit your workflow! 🚀</content>
<parameter name="filePath">linuxinstaller/wiki/Configuration-Guide.md