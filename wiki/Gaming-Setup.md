# Gaming Setup

Complete guide to gaming on Linux with LinuxInstaller.

## 🎮 Gaming Suite Overview

LinuxInstaller includes comprehensive gaming support with automatic GPU detection, driver installation, and performance optimization.

### What's Included

- **Steam** - Gaming platform installation and configuration
- **Wine** - Windows compatibility layer
- **Proton** - Steam Play for Windows games
- **GPU Drivers** - Automatic AMD/Intel driver installation
- **Performance Tools** - MangoHud monitoring and GameMode optimization
- **Gaming Libraries** - Vulkan, OpenGL, and gaming dependencies

## 🚀 Quick Gaming Setup

### Enable Gaming During Installation

1. Run LinuxInstaller in **Standard** or **Minimal** mode
2. When prompted "Install Gaming Package Suite?", answer **Yes**
3. The script will install and configure gaming components

### Manual Gaming Setup

If you skipped gaming during installation:

```bash
# Install gaming packages manually
sudo pacman -S steam wine mangohud gamemode  # Arch
sudo apt install steam wine mangohud gamemode # Ubuntu
sudo dnf install steam wine mangohud gamemode # Fedora
```

## 🎯 GPU Driver Setup

### AMD GPU (Automatic)

LinuxInstaller automatically detects and installs AMD GPU drivers:

**Arch Linux:**
```bash
# Mesa + Vulkan drivers
mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon
```

**Fedora:**
```bash
# Mesa Vulkan drivers
mesa-vulkan-drivers mesa-vulkan-drivers.i686
```

**Ubuntu/Debian:**
```bash
# Mesa Vulkan drivers
mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386
```

### Intel GPU (Automatic)

Intel integrated graphics are automatically configured:

**Arch Linux:**
```bash
# Mesa + Intel media driver
mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver
```

**Fedora:**
```bash
# Mesa Vulkan drivers with Intel support
mesa-vulkan-drivers mesa-vulkan-drivers.i686
```

**Ubuntu/Debian:**
```bash
# Mesa Vulkan drivers with Intel support
mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386
```

### NVIDIA GPU (Manual Installation Required)

⚠️ **NVIDIA drivers cannot be installed automatically due to licensing restrictions.**

**After running LinuxInstaller:**

#### Arch Linux
```bash
sudo pacman -S nvidia nvidia-utils lib32-nvidia-utils
sudo reboot
```

#### Ubuntu/Debian
```bash
sudo apt install nvidia-driver
sudo reboot
```

#### Fedora
```bash
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
sudo reboot
```

**Verify Installation:**
```bash
nvidia-smi
vulkaninfo | grep NVIDIA
```

## 🕹️ Steam Setup

### First-Time Steam Setup

1. Launch Steam:
   ```bash
   steam
   ```

2. Login to your Steam account

3. In Steam settings:
   - **Steam Play**: Enable for all titles
   - **Shader Pre-Caching**: Enable
   - **Family Sharing**: Configure if needed

### Proton Version Selection

For best compatibility:
1. Right-click game → Properties
2. **Compatibility** → Check "Force the use of a specific Steam Play compatibility tool"
3. Select **Proton Experimental** or **Proton-GE** for latest features

## 🍷 Wine Configuration

### Basic Wine Setup

```bash
# Configure Wine
winecfg

# Install common dependencies
winetricks corefonts vcrun6
```

### Wine Prefix Management

```bash
# Create new Wine prefix for specific games
export WINEPREFIX=~/.wine-game
winecfg

# Launch game with specific prefix
export WINEPREFIX=~/.wine-game
wine game.exe
```

## 📊 Performance Monitoring

### MangoHud Setup

MangoHud provides real-time performance monitoring:

```bash
# Launch game with MangoHud
mangohud steam

# Or per-game in Steam:
# Right-click game → Properties → General → Launch Options
# Add: mangohud %command%
```

### GameMode Integration

GameMode optimizes system performance for gaming:

```bash
# Manual activation
gamemoded -t

# Check status
gamemoded -s
```

### Steam Launch Options

Common launch options for better performance:

```
# High-performance GPU
__GL_SHADER_DISK_CACHE=1 __GL_SHADER_DISK_CACHE_PATH=/tmp %command%

# Vulkan async compute
RADV_PERFTEST=all %command%

# Feral Gamemode
gamemoded %command%

# Performance monitoring
mangohud %command%
```

## 🎮 Game-Specific Optimizations

### Proton-Compatible Games

Most modern games work well with Proton. For problematic games:

1. **Use Proton-GE**: Download from [Proton-GE releases](https://github.com/GloriousEggroll/proton-ge-custom/releases)
2. **Enable Steam Play**: Force latest Proton version
3. **Install Dependencies**: Use Protontricks for additional DLLs

### Wine-Only Games

For games requiring Wine:

```bash
# Install with Lutris (recommended)
sudo pacman -S lutris     # Arch
sudo apt install lutris   # Ubuntu
sudo dnf install lutris   # Fedora

# Or manual Wine setup
export WINEARCH=win64
wine game-installer.exe
```

## 🛠️ Troubleshooting Gaming Issues

### Steam Won't Launch

**Check Dependencies:**
```bash
# Arch Linux
sudo pacman -S steam-native-runtime

# Ubuntu/Debian
sudo apt install steam steam-libs-amd64 steam-libs-i386

# Fedora
sudo dnf install steam
```

**Clear Steam Cache:**
```bash
# Close Steam completely
pkill -f steam

# Remove cache
rm -rf ~/.steam/steam/appcache
rm -rf ~/.steam/steam/steamapps/shadercache*

# Restart Steam
steam
```

### Game Performance Issues

**Check GPU Usage:**
```bash
# Monitor GPU
nvidia-smi -l 1    # NVIDIA
radeontop          # AMD
intel-gpu-top      # Intel
```

**System Monitoring:**
```bash
# CPU/Memory usage
htop
btop

# Disk I/O
iotop
```

**Shader Pre-Caching:**
```bash
# Force shader compilation
PROTON_USE_WINED3D=1 %command%
```

### Vulkan Issues

**Verify Vulkan Installation:**
```bash
# Check Vulkan support
vulkaninfo | head -20

# Test Vulkan
vkcube
```

**AMD GPU Specific:**
```bash
# Check AMDGPU driver
lsmod | grep amdgpu

# RADV debug options
RADV_DEBUG=all %command%
```

**Intel GPU Specific:**
```bash
# Check i915 driver
lsmod | grep i915

# Intel Vulkan debug
INTEL_DEBUG=all %command%
```

### Wine Problems

**Wine Version Issues:**
```bash
# Check Wine version
wine --version

# Update Wine
sudo pacman -S wine-staging  # Arch
sudo apt install wine-staging # Ubuntu
```

**DLL Dependencies:**
```bash
# Install common DLLs
winetricks vcrun2019 dotnet48 d3dcompiler_47

# DirectX dependencies
winetricks d3dx9 d3dx10 d3dx11
```

### Audio Issues

**PulseAudio/JACK Conflicts:**
```bash
# Check audio setup
pactl list sinks

# Restart audio service
systemctl --user restart pulseaudio
```

**Wine Audio:**
```bash
# Force PulseAudio in Wine
export PULSE_LATENCY_MSEC=60
wine game.exe
```

## 🎯 Advanced Gaming Setup

### Multiple GPU Setup (Hybrid Graphics)

For laptops with both integrated and discrete GPUs:

```bash
# Check available GPUs
lspci | grep VGA

# Launch on specific GPU (NVIDIA)
__GLX_VENDOR_LIBRARY_NAME=nvidia %command%

# Launch on integrated GPU
__GLX_VENDOR_LIBRARY_NAME=mesa %command%
```

### Custom Proton Versions

**Install Custom Proton:**
```bash
# Download Proton-GE
wget https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton7-43/proton-ge-custom_7.43.tar.gz

# Extract to Steam compatibility tools
tar -xzf proton-ge-custom_7.43.tar.gz -C ~/.steam/root/compatibilitytools.d/
```

### Feral Gamemode

**Custom Gamemode Configuration:**
```bash
# Edit gamemode config
sudo nano /etc/gamemode.ini

# Example customizations:
[general]
desiredgov=performance
softrealtime=yes

[custom]
start=notify-send "GameMode started"
end=notify-send "GameMode stopped"
```

## 🎮 Gaming Communities & Resources

### Linux Gaming Resources

- **ProtonDB**: [protondb.com](https://www.protondb.com/) - Game compatibility ratings
- **Lutris**: [lutris.net](https://lutris.net/) - Game management platform
- **GamingOnLinux**: [gamingonlinux.com](https://www.gamingonlinux.com/) - Linux gaming news

### Community Support

- **Steam for Linux Community**: Active troubleshooting and tips
- **r/linux_gaming**: Reddit community for Linux gaming
- **Discord Servers**: Various Linux gaming communities

### Performance Optimization Guides

- **Arch Wiki Gaming**: Comprehensive Linux gaming guide
- **Fedora Gaming**: RPM Fusion gaming documentation
- **Ubuntu Gaming**: Official gaming documentation

## 📊 Benchmarking & Testing

### Performance Testing

```bash
# Run benchmarks
mangohud glxgears    # OpenGL benchmark
mangohud vkcube      # Vulkan benchmark

# Steam performance overlay
# In Steam: Shift+Tab during gameplay
```

### System Monitoring

```bash
# Real-time monitoring
mangohud steam

# Background monitoring
gamemoded -d        # Run GameMode daemon
```

## 🚀 Future Gaming Improvements

### Planned Features

- **Lutris Integration**: Automatic game installer configuration
- **FSR Support**: FidelityFX Super Resolution
- **Cloud Gaming**: Support for cloud gaming platforms
- **Controller Configuration**: Automatic controller setup

### Contributing

Help improve LinuxInstaller's gaming support:

- Test games and report compatibility
- Suggest performance optimizations
- Contribute to gaming documentation
- Report bugs and request features

---

**Enjoy gaming on Linux! Your gaming experience should rival Windows with proper setup.** 🎮🚀</content>
<parameter name="filePath">linuxinstaller/wiki/Gaming-Setup.md