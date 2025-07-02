#!/usr/bin/env bash
set -uo pipefail

# Source common functions and variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR"
source "$SCRIPTS_DIR/common.sh"

install_gamemode() {
    step "Installing GameMode (Arch)"
    if pacman -Q gamemode &>/dev/null; then
        log_success "GameMode is already installed."
        return 0
    fi
    if sudo pacman -Sy --noconfirm gamemode lib32-gamemode; then
        log_success "GameMode installed successfully."
        return 0
    else
        log_error "Failed to install GameMode."
        return 1
    fi
}

# Detect if running inside a virtual machine
is_vm() {
    # Check for common VM indicators
    if grep -q -i 'hypervisor' /proc/cpuinfo; then
        return 0
    fi
    if systemd-detect-virt --quiet; then
        return 0
    fi
    if [ -d /proc/xen ]; then
        return 0
    fi
    return 1
}

configure_gamemode() {
    step "Configuring GameMode system optimizations"
    if ! command -v gamemoded &>/dev/null; then
        log_warning "GameMode is not installed. Skipping configuration."
        return 0
    fi
    # Detect if running in a VM
    if is_vm; then
        log_info "Detected virtual machine environment. Creating minimal GameMode config."
        CONFIG_DIR="$HOME/.config"
        CONFIG_FILE="$CONFIG_DIR/gamemode.ini"
        mkdir -p "$CONFIG_DIR"
        cat > "$CONFIG_FILE" <<EOF
[general]
renice=10
softrealtime=true
softrealtime_limit=95
EOF
        chmod 644 "$CONFIG_FILE"
        log_success "Minimal GameMode config written to $CONFIG_FILE (VM detected)"
        return 0
    fi
# Detect session type (Wayland or X11)
SESSION_TYPE=${XDG_SESSION_TYPE:-$(loginctl show-session "$(loginctl | grep "$(whoami)" | awk '{print $1}')" -p Type | cut -d= -f2)}
    log_info "Detected session type: $SESSION_TYPE"
# Detect GPU
GPU_VENDOR=$(lspci | grep -E "VGA|3D" | grep -iE "nvidia|amd|ati" | awk '{print tolower($0)}')
if echo "$GPU_VENDOR" | grep -q "nvidia"; then
    GPU="nvidia"
elif echo "$GPU_VENDOR" | grep -qE "amd|ati"; then
    GPU="amd"
else
    GPU="unknown"
fi
    log_info "Detected GPU: $GPU"
# GameMode config
CONFIG_DIR="$HOME/.config"
CONFIG_FILE="$CONFIG_DIR/gamemode.ini"
mkdir -p "$CONFIG_DIR"
cat > "$CONFIG_FILE" <<EOF
[general]
renice=10
softrealtime=true
softrealtime_limit=95

[cpu]
governor=performance

[custom]
start_script=/usr/local/bin/gamemode_start
end_script=/usr/local/bin/gamemode_end
EOF
chmod 644 "$CONFIG_FILE"
    log_success "GameMode config written to $CONFIG_FILE"
# GameMode Start Script
START_SCRIPT="/usr/local/bin/gamemode_start"
sudo tee "$START_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# Set performance governor
if command -v cpupower &>/dev/null; then
    sudo cpupower frequency-set -g performance &>/dev/null
fi
# Lower swappiness
echo 10 | sudo tee /proc/sys/vm/swappiness > /dev/null
# AMD: set performance
if [ "$GPU" = "amd" ]; then
    AMD_PATH=\$(find /sys/class/drm/card*/device/power_dpm_force_performance_level 2>/dev/null | head -n1)
    if [ -n "\$AMD_PATH" ]; then
        echo high | sudo tee "\$AMD_PATH" > /dev/null
    fi
fi
# X11-specific tweaks
if [ "$SESSION_TYPE" = "x11" ]; then
    # KDE: suspend compositor
    if pgrep -x kwin_x11 &>/dev/null; then
        qdbus org.kde.KWin /Compositor suspend || true
    fi
    # NVIDIA: performance mode
    if [ "$GPU" = "nvidia" ] && command -v nvidia-settings &>/dev/null; then
        export DISPLAY=:0
        export XAUTHORITY=\$(sudo -u $USER bash -c 'echo $XAUTHORITY')
        nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=1" &>/dev/null
    fi
fi
EOF
# GameMode End Script
END_SCRIPT="/usr/local/bin/gamemode_end"
sudo tee "$END_SCRIPT" > /dev/null <<EOF
#!/bin/bash
# AMD: revert to auto
if [ "$GPU" = "amd" ]; then
    AMD_PATH=\$(find /sys/class/drm/card*/device/power_dpm_force_performance_level 2>/dev/null | head -n1)
    if [ -n "\$AMD_PATH" ]; then
        echo auto | sudo tee "\$AMD_PATH" > /dev/null
    fi
fi
# X11-specific revert
if [ "$SESSION_TYPE" = "x11" ]; then
    # KDE: resume compositor
    if pgrep -x kwin_x11 &>/dev/null; then
        qdbus org.kde.KWin /Compositor resume || true
    fi
    # NVIDIA: revert to adaptive
    if [ "$GPU" = "nvidia" ] && command -v nvidia-settings &>/dev/null; then
        export DISPLAY=:0
        export XAUTHORITY=\$(sudo -u $USER bash -c 'echo $XAUTHORITY')
        nvidia-settings -a "[gpu:0]/GpuPowerMizerMode=0" &>/dev/null
    fi
fi
EOF
sudo chmod +x "$START_SCRIPT" "$END_SCRIPT"
    log_success "GameMode start/end scripts installed."
    log_success "GameMode with safe system optimizations configured successfully."
}

# Main logic
install_gamemode && configure_gamemode
