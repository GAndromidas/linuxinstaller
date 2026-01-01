# Troubleshooting

This page covers common issues and their solutions when using LinuxInstaller.

## 🚫 Installation Issues

### Script Won't Start

**Symptoms:**
- Command not found error
- Permission denied
- Script doesn't execute

**Solutions:**

1. **Check Permissions:**
   ```bash
   ls -la install.sh
   chmod +x install.sh
   ```

2. **Verify Download:**
   ```bash
   # Check file integrity
   file install.sh
   head -n 5 install.sh
   ```

3. **Check System Requirements:**
   ```bash
   # Verify Linux system
   uname -a

   # Check sudo access
   sudo whoami
   ```

### Network Connection Issues

**Symptoms:**
- "No internet connection detected"
- Package download failures
- Connection timeouts

**Solutions:**

1. **Test Connectivity:**
   ```bash
   ping -c 3 8.8.8.8
   ping -c 3 google.com
   ```

2. **Check DNS:**
   ```bash
   cat /etc/resolv.conf
   nslookup github.com
   ```

3. **Proxy Settings:**
   ```bash
   export http_proxy="http://proxy.company.com:8080"
   export https_proxy="http://proxy.company.com:8080"
   ```

4. **Firewall Issues:**
   ```bash
   sudo ufw status
   sudo ufw allow out 80
   sudo ufw allow out 443
   ```

## 📦 Package Installation Problems

### Package Not Found

**Symptoms:**
- "package not found" errors
- Installation failures

**Solutions:**

1. **Update Package Database:**
   ```bash
   # Arch Linux
   sudo pacman -Syy

   # Ubuntu/Debian
   sudo apt update

   # Fedora
   sudo dnf check-update
   ```

2. **Check Package Names:**
   ```bash
   # Arch Linux
   pacman -Ss package_name

   # Ubuntu/Debian
   apt search package_name

   # Fedora
   dnf search package_name
   ```

3. **Repository Issues:**
   ```bash
   # Check enabled repositories
   cat /etc/pacman.conf  # Arch
   cat /etc/apt/sources.list  # Debian/Ubuntu
   cat /etc/dnf/dnf.conf  # Fedora
   ```

### Dependency Conflicts

**Symptoms:**
- Package conflicts during installation
- Dependency resolution failures

**Solutions:**

1. **Clean Package Cache:**
   ```bash
   # Arch Linux
   sudo pacman -Scc

   # Ubuntu/Debian
   sudo apt clean && sudo apt autoclean

   # Fedora
   sudo dnf clean all
   ```

2. **Fix Broken Packages:**
   ```bash
   # Ubuntu/Debian
   sudo apt --fix-broken install
   sudo dpkg --configure -a

   # Fedora
   sudo dnf distro-sync
   ```

## 🎨 UI and Display Issues

### Gum Not Working

**Symptoms:**
- Fallback to text menus
- "gum command not found"
- Missing visual elements

**Solutions:**

1. **Install Gum:**
   ```bash
   # Arch Linux
   sudo pacman -S gum

   # Ubuntu/Debian
   sudo apt install gum

   # Fedora
   sudo dnf install gum
   ```

2. **Check Terminal Support:**
   ```bash
   echo $TERM
   tput colors  # Should show 256 or more
   ```

3. **Force Text Mode:**
   ```bash
   # If gum causes issues
   export NO_GUM=true
   sudo ./install.sh
   ```

### Color Issues

**Symptoms:**
- Colors not displaying correctly
- Invisible text
- Garbled output

**Solutions:**

1. **Check Terminal Settings:**
   ```bash
   # Verify color support
   echo -e "\033[31mRed\033[0m \033[32mGreen\033[0m \033[34mBlue\033[0m"
   ```

2. **TERM Variable:**
   ```bash
   export TERM=xterm-256color
   ```

3. **Terminal Emulator:**
   - Ensure you're using a modern terminal (GNOME Terminal, Konsole, Alacritty)
   - Check terminal preferences for color support

## 🔒 Security Configuration Issues

### Firewall Problems

**Symptoms:**
- UFW not starting
- Firewall rules not applied
- Network connectivity issues

**Solutions:**

1. **Check UFW Status:**
   ```bash
   sudo ufw status
   sudo systemctl status ufw
   ```

2. **Reset Firewall:**
   ```bash
   sudo ufw --force reset
   sudo ufw enable
   ```

3. **Check Rules:**
   ```bash
   sudo ufw status verbose
   ```

### SSH Issues

**Symptoms:**
- SSH service not starting
- Connection refused
- Authentication failures

**Solutions:**

1. **Check SSH Service:**
   ```bash
   sudo systemctl status sshd
   sudo systemctl enable sshd
   sudo systemctl start sshd
   ```

2. **Verify Configuration:**
   ```bash
   sudo sshd -t  # Test configuration
   cat /etc/ssh/sshd_config
   ```

3. **Firewall Rules:**
   ```bash
   sudo ufw allow ssh
   ```

### Fail2ban Issues

**Symptoms:**
- Fail2ban not protecting SSH
- Service not starting

**Solutions:**

1. **Check Status:**
   ```bash
   sudo systemctl status fail2ban
   sudo fail2ban-client status
   ```

2. **Check Logs:**
   ```bash
   sudo tail -f /var/log/fail2ban.log
   ```

3. **Verify Jails:**
   ```bash
   sudo fail2ban-client status sshd
   ```

## ⚡ Performance Issues

### CPU Governor Not Applied

**Symptoms:**
- CPU stays in wrong power mode
- Performance service not running

**Solutions:**

1. **Check Current Governor:**
   ```bash
   cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```

2. **Available Governors:**
   ```bash
   cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
   ```

3. **Manual Setting:**
   ```bash
   echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```

4. **Service Issues:**
   ```bash
   sudo systemctl status cpu-performance
   sudo systemctl enable cpu-performance
   sudo systemctl start cpu-performance
   ```

### ZRAM Not Working

**Symptoms:**
- No compressed swap
- Memory pressure issues

**Solutions:**

1. **Check ZRAM Status:**
   ```bash
   swapon -s | grep zram
   ```

2. **ZRAM Modules:**
   ```bash
   lsmod | grep zram
   ```

3. **Manual Setup:**
   ```bash
   sudo modprobe zram
   echo lz4 | sudo tee /sys/block/zram0/comp_algorithm
   echo 2G | sudo tee /sys/block/zram0/disksize
   sudo mkswap /dev/zram0
   sudo swapon /dev/zram0
   ```

## 🖥️ Desktop Environment Issues

### KDE Plasma Problems

**Symptoms:**
- Shortcuts not working
- Theme not applied
- Plasma not starting

**Solutions:**

1. **Reapply Shortcuts:**
   ```bash
   # Backup current shortcuts
   cp ~/.config/kglobalshortcutsrc ~/.config/kglobalshortcutsrc.backup

   # Reapply LinuxInstaller shortcuts
   cp /path/to/linuxinstaller/configs/arch/kglobalshortcutsrc ~/.config/kglobalshortcutsrc

   # Restart Plasma
   kquitapp5 plasmashell && kstart5 plasmashell
   ```

2. **Theme Issues:**
   ```bash
   # Reset Plasma theme
   lookandfeeltool -a org.kde.breeze.desktop
   ```

### GNOME Issues

**Symptoms:**
- Extensions not working
- Theme not applied

**Solutions:**

1. **Check Extension Support:**
   ```bash
   gnome-extensions list
   ```

2. **Enable Extensions:**
   ```bash
   gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com
   ```

3. **Reset Theme:**
   ```bash
   gsettings reset org.gnome.desktop.interface gtk-theme
   gsettings reset org.gnome.desktop.wm.preferences theme
   ```

## 🐚 Shell Configuration Issues

### Zsh Not Default

**Symptoms:**
- Shell remains bash after installation
- Zsh configuration not loaded

**Solutions:**

1. **Change Default Shell:**
   ```bash
   chsh -s $(which zsh) $USER
   ```

2. **Manual Shell Change:**
   ```bash
   sudo usermod -s $(which zsh) $USER
   ```

3. **Logout/Login:**
   ```bash
   # Logout and login again, or:
   exec zsh
   ```

### Starship Not Loading

**Symptoms:**
- No prompt customization
- Starship command not found

**Solutions:**

1. **Check Installation:**
   ```bash
   which starship
   starship --version
   ```

2. **Initialize Starship:**
   ```bash
   # Add to ~/.zshrc if missing
   echo 'eval "$(starship init zsh)"' >> ~/.zshrc
   ```

3. **Reload Configuration:**
   ```bash
   source ~/.zshrc
   ```

### Fastfetch Issues

**Symptoms:**
- Fastfetch not showing system info
- Configuration not applied

**Solutions:**

1. **Check Installation:**
   ```bash
   which fastfetch
   fastfetch --version
   ```

2. **Configuration Location:**
   ```bash
   ls -la ~/.config/fastfetch/
   cat ~/.config/fastfetch/config.jsonc
   ```

3. **Test Fastfetch:**
   ```bash
   fastfetch
   ```

## 🎮 Gaming Issues

### GPU Driver Problems

**Symptoms:**
- GPU not recognized
- Vulkan not working
- Games not launching

**Solutions:**

1. **Check GPU:**
   ```bash
   lspci | grep VGA
   ```

2. **AMD GPU:**
   ```bash
   # Verify drivers
   lsmod | grep amdgpu
   vulkaninfo | grep GPU
   ```

3. **Intel GPU:**
   ```bash
   # Check drivers
   lsmod | grep i915
   vulkaninfo | grep GPU
   ```

4. **NVIDIA GPU:**
   ```bash
   # Install drivers (manual)
   sudo pacman -S nvidia nvidia-utils  # Arch
   sudo apt install nvidia-driver       # Ubuntu
   sudo dnf install akmod-nvidia        # Fedora

   # Reboot required
   sudo reboot
   ```

### Steam Issues

**Symptoms:**
- Steam not launching
- Games not installing

**Solutions:**

1. **Check Dependencies:**
   ```bash
   # Arch Linux
   sudo pacman -S steam steam-native-runtime

   # Ubuntu/Debian
   sudo apt install steam

   # Fedora
   sudo dnf install steam
   ```

2. **Launch Steam:**
   ```bash
   # With Proton experimental
   STEAM_PROTON_VERSION=experimental steam
   ```

### Wine Problems

**Symptoms:**
- Wine not working
- Windows applications crashing

**Solutions:**

1. **Check Wine Installation:**
   ```bash
   wine --version
   winetricks --version
   ```

2. **Wine Configuration:**
   ```bash
   winecfg
   ```

3. **Common Dependencies:**
   ```bash
   # Arch Linux
   sudo pacman -S wine winetricks

   # Ubuntu/Debian
   sudo apt install wine winetricks

   # Fedora
   sudo dnf install wine winetricks
   ```

## 🔧 Advanced Troubleshooting

### Debug Mode

Run with maximum verbosity:

```bash
sudo ./install.sh --verbose --dry-run
```

### Log Files

Check system logs:

```bash
# System logs
sudo journalctl -f

# Package manager logs
/var/log/pacman.log    # Arch
/var/log/apt/          # Ubuntu/Debian
/var/log/dnf.log       # Fedora
```

### Recovery Options

1. **Partial Installation Recovery:**
   ```bash
   # Skip completed steps
   export SKIP_COMPLETED=true
   sudo ./install.sh
   ```

2. **Clean Reinstall:**
   ```bash
   # Remove LinuxInstaller configurations
   rm -rf ~/.config/starship.toml
   rm -rf ~/.config/fastfetch/
   sudo ufw --force reset
   ```

3. **System Rollback:**
   ```bash
   # If using Btrfs snapshots
   sudo snapper list
   sudo snapper rollback <snapshot-number>
   ```

## 📞 Getting Help

### Before Asking for Help

1. **Gather Information:**
   ```bash
   # System info
   uname -a
   cat /etc/os-release

   # Installation logs
   sudo journalctl --since "1 hour ago" | grep -i linuxinstaller
   ```

2. **Try Basic Fixes:**
   - Reboot system
   - Update packages
   - Check internet connection
   - Verify permissions

### Where to Get Help

- **📖 Documentation**: Check this wiki first
- **❓ FAQ**: [[FAQ|FAQ]] page for common questions
- **🐛 Bug Reports**: [GitHub Issues](https://github.com/GAndromidas/linuxinstaller/issues)
- **💬 Discussions**: [GitHub Discussions](https://github.com/GAndromidas/linuxinstaller/discussions)
- **📧 General Help**: Create a new discussion thread

### Creating Effective Bug Reports

When reporting issues, include:

1. **System Information:**
   - Distribution and version
   - Kernel version (`uname -a`)
   - Hardware details

2. **Error Messages:**
   - Exact error output
   - When the error occurs

3. **Steps to Reproduce:**
   - Commands run
   - Installation options selected

4. **Expected vs Actual Behavior:**
   - What you expected
   - What actually happened

This helps maintainers quickly identify and fix issues! 🚀</content>
<parameter name="filePath">linuxinstaller/wiki/Troubleshooting.md