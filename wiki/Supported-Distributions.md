# Supported Distributions

Detailed information about Linux distributions supported by LinuxInstaller.

## 🐧 Arch Linux

### Overview
Arch Linux is a lightweight, rolling-release distribution that stays up-to-date with the latest software.

### Support Level: ⭐⭐⭐⭐⭐ **Full Support**

### Features
- ✅ **AUR Integration**: Automatic yay installation and AUR package support
- ✅ **Pacman Optimization**: Parallel downloads, ILoveCandy, package cache cleaning
- ✅ **Plymouth**: Boot splash screen configuration
- ✅ **Multilib**: 32-bit software support for gaming
- ✅ **Rate Mirrors**: Automatic mirror optimization
- ✅ **ZRAM**: systemd-zram-generator integration

### Package Managers
- **Primary**: pacman (native packages)
- **AUR**: yay (AUR helper)
- **Universal**: flatpak (universal packages)

### Recommended Installation
```bash
# Arch Linux installation
wget -qO- https://raw.githubusercontent.com/GAndromidas/linuxinstaller/main/install.sh | bash
```

### Known Limitations
- AUR packages require user interaction for PGP key imports (rare)
- Some AUR packages may require manual dependency resolution

---

## 🍥 Fedora

### Overview
Fedora is a cutting-edge Fedora Project distribution with regular releases and strong focus on free software.

### Support Level: ⭐⭐⭐⭐⭐ **Full Support**

### Features
- ✅ **RPM Fusion**: Automatic repository setup
- ✅ **DNF Optimization**: Fastest mirror selection, parallel downloads
- ✅ **Firewalld**: Modern firewall management
- ✅ **SELinux**: Security framework integration
- ✅ **COPR**: Community package repository support
- ✅ **ZRAM**: systemd-zram-generator integration

### Package Managers
- **Primary**: dnf (RPM packages)
- **Community**: COPR repositories
- **Universal**: flatpak, snap

### Recommended Installation
```bash
# Fedora installation
wget -qO- https://raw.githubusercontent.com/GAndromidas/linuxinstaller/main/install.sh | bash
```

### Known Limitations
- Some packages may require RPM Fusion for full functionality
- SELinux policies may need adjustment for certain applications

---

## 🐌 Debian

### Overview
Debian is a stable, universally-compatible distribution known for its reliability and package quality.

### Support Level: ⭐⭐⭐⭐⭐ **Full Support**

### Features
- ✅ **APT Optimization**: Sources configuration, security updates
- ✅ **Backports**: Access to newer software versions
- ✅ **UFW**: Uncomplicated Firewall integration
- ✅ **AppArmor**: Mandatory access control
- ✅ **Multiarch**: Architecture mixing support
- ✅ **Non-free**: Firmware and driver access

### Package Managers
- **Primary**: apt (DEB packages)
- **Universal**: flatpak, snap

### Recommended Installation
```bash
# Debian installation
wget -qO- https://raw.githubusercontent.com/GAndromidas/linuxinstaller/main/install.sh | bash
```

### Known Limitations
- Some software may be older due to stability focus
- Backports required for latest versions of some applications

---

## 🐧 Ubuntu

### Overview
Ubuntu is a popular Debian-based distribution with regular releases and strong community support.

### Support Level: ⭐⭐⭐⭐⭐ **Full Support**

### Features
- ✅ **APT Optimization**: Sources configuration, PPAs
- ✅ **Snap Integration**: Canonical's universal package system
- ✅ **UFW**: Uncomplicated Firewall (default)
- ✅ **AppArmor**: Application security framework
- ✅ **Multiarch**: Cross-architecture support
- ✅ **Universe/Multiverse**: Extended software repositories

### Package Managers
- **Primary**: apt (DEB packages)
- **Universal**: snap, flatpak

### Recommended Installation
```bash
# Ubuntu installation
wget -qO- https://raw.githubusercontent.com/GAndromidas/linuxinstaller/main/install.sh | bash
```

### Known Limitations
- Snap packages may have slower startup times
- Some GNOME extensions require manual installation

---

## 📊 Feature Comparison

| Feature | Arch Linux | Fedora | Debian | Ubuntu |
|---------|------------|--------|--------|--------|
| **Package Manager** | pacman + yay | dnf + COPR | apt | apt + snap |
| **Release Model** | Rolling | Point | Point | Point |
| **Default Firewall** | UFW | firewalld | UFW | UFW |
| **Security Framework** | AppArmor | SELinux | AppArmor | AppArmor |
| **Gaming Support** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Development Tools** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Desktop Environments** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Ease of Use** | 🔧 Advanced | 🔧 Advanced | 🟢 Intermediate | 🟢 Beginner |

---

## 🔧 Distribution-Specific Configurations

### Arch Linux Optimizations

```bash
# Pacman configuration (/etc/pacman.conf)
ParallelDownloads = 10
ILoveCandy
VerbosePkgLists
Color

# Mirror optimization
rate-mirrors --allow-root arch | sudo tee /etc/pacman.d/mirrorlist
```

### Fedora Optimizations

```bash
# DNF configuration (/etc/dnf/dnf.conf)
fastestmirror=True
max_parallel_downloads=10
defaultyes=True

# RPM Fusion setup
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

### Debian Optimizations

```bash
# APT configuration (/etc/apt/apt.conf.d/99linuxinstaller)
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Languages "none";

# Sources configuration (/etc/apt/sources.list)
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
```

### Ubuntu Optimizations

```bash
# APT configuration
sudo add-apt-repository universe
sudo add-apt-repository multiverse
sudo add-apt-repository restricted

# Snap configuration
sudo snap set system refresh.retain=2
sudo snap set system snapshots.automatic.retention=7d
```

---

## 🎯 Recommended Distributions

### For Beginners
- **Ubuntu**: User-friendly, excellent documentation, large community
- **Fedora**: Modern software, good balance of stability and features

### For Advanced Users
- **Arch Linux**: Bleeding-edge software, complete control, learning experience
- **Debian**: Rock-solid stability, server-grade reliability

### For Gaming
- **All distributions** provide excellent gaming support
- **Arch Linux**: Latest GPU drivers and gaming tools
- **Ubuntu**: Largest compatibility with Windows games via Proton

### For Development
- **Arch Linux**: Always up-to-date development tools
- **Ubuntu**: Most popular for development, extensive documentation
- **Fedora**: Cutting-edge development tools and libraries

### For Servers
- **Debian**: Most stable and secure for production servers
- **Ubuntu Server**: Regular LTS releases, strong commercial support
- **Fedora Server**: Latest server technologies and features

---

## 🔄 Switching Distributions

### From Ubuntu to Other Distributions

**To Fedora:**
```bash
# Backup important data
# Download Fedora ISO
# Install Fedora
# Run LinuxInstaller
```

**To Arch Linux:**
```bash
# More complex migration
# Consider fresh installation
# Use LinuxInstaller post-install
```

### Migration Considerations

1. **Backup Data**: Always backup important files and configurations
2. **Application Compatibility**: Check if your applications are available
3. **Hardware Support**: Verify hardware compatibility
4. **Learning Curve**: Some distributions have steeper learning curves

### Dual Boot Considerations

- **GRUB Configuration**: May need manual GRUB updates
- **Bootloader Order**: Set preferred distribution as default
- **Shared Partitions**: Use common data partitions between distributions

---

## 🆘 Distribution-Specific Issues

### Arch Linux Issues

**Common Problems:**
- AUR package building failures
- Mirror sync issues
- Pacman database corruption

**Solutions:**
```bash
# Fix pacman database
sudo rm -f /var/lib/pacman/db.lck
sudo pacman -Syy

# Rebuild AUR packages
yay -S --rebuild package_name
```

### Fedora Issues

**Common Problems:**
- RPM Fusion conflicts
- SELinux denials
- DNF transaction failures

**Solutions:**
```bash
# Fix DNF issues
sudo rm -f /var/lib/dnf/history.sqlite
sudo dnf clean all

# SELinux troubleshooting
sudo ausearch -m avc -ts recent
sudo setsebool -P boolean_name on
```

### Debian/Ubuntu Issues

**Common Problems:**
- APT dependency issues
- Release upgrade problems
- Package pinning conflicts

**Solutions:**
```bash
# Fix APT issues
sudo apt --fix-broken install
sudo dpkg --configure -a

# Clean package cache
sudo apt clean && sudo apt autoclean
```

---

## 🤝 Contributing New Distributions

### Requirements for New Distribution Support

1. **Package Manager Abstraction**: Must support the package management interface
2. **Systemd Compatibility**: Services must use systemd
3. **Repository Structure**: Clear package repositories and update mechanisms
4. **Community Support**: Active community and documentation

### Adding Distribution Support

See the [[Development Guide|Development-Guide]] for detailed instructions on adding new distribution support.

### Requested Distributions

Community-requested distributions (in order of popularity):
1. **Linux Mint** (Ubuntu-based, high demand)
2. **openSUSE** (RPM-based, enterprise features)
3. **Gentoo** (source-based, advanced users)
4. **Manjaro** (Arch-based, user-friendly)
5. **Pop!_OS** (Ubuntu-based, developer-focused)

---

## 📞 Getting Help

### Distribution-Specific Help

- **Arch Linux**: [Arch Wiki](https://wiki.archlinux.org/), [Arch Forums](https://bbs.archlinux.org/)
- **Fedora**: [Fedora Documentation](https://docs.fedoraproject.org/), [Fedora Discussion](https://discussion.fedoraproject.org/)
- **Debian**: [Debian Documentation](https://www.debian.org/doc/), [Debian Forums](https://forums.debian.net/)
- **Ubuntu**: [Ubuntu Documentation](https://help.ubuntu.com/), [Ask Ubuntu](https://askubuntu.com/)

### LinuxInstaller Support

- **General Issues**: [GitHub Issues](https://github.com/GAndromidas/linuxinstaller/issues)
- **Discussions**: [GitHub Discussions](https://github.com/GAndromidas/linuxinstaller/discussions)
- **Documentation**: This wiki

---

**Choose the distribution that best fits your needs and workflow!** 🚀</content>
<parameter name="filePath">linuxinstaller/wiki/Supported-Distributions.md