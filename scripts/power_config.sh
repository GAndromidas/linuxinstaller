#!/bin/bash
# Power management helper for LinuxInstaller
# - Detects CPU/GPU/RAM and exposes helper to show that info.
# - Installs/configures appropriate power management tooling:
#   Prefer: power-profiles-daemon (and configure default profile)
#   Fallback: cpupower (if cpufreq support) or tuned (legacy/older systems)
#
# Designed to be sourced by the main installer (install.sh).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Common helpers (log_* , step, install_pkg, supports_gum, etc.)
# These are present in the main install environment; sourcing here if available.
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    source "$SCRIPT_DIR/common.sh"
fi
if [ -f "$SCRIPT_DIR/distro_check.sh" ]; then
    source "$SCRIPT_DIR/distro_check.sh"
fi

# -----------------------------------------------------------------------------
# System detection helpers
# -----------------------------------------------------------------------------

# Detect and populate system information (OS, CPU, GPU, RAM)
detect_system_info() {
    # Populates globals:
    # - DETECTED_OS
    # - DETECTED_CPU
    # - DETECTED_GPU
    # - DETECTED_RAM
    DETECTED_OS="${PRETTY_NAME:-$(uname -srv)}"

    # CPU (prefer lscpu)
    if command -v lscpu >/dev/null 2>&1; then
        DETECTED_CPU="$(lscpu 2>/dev/null | awk -F: '/^Model name:/ {print $2; exit}' | xargs || true)"
    else
        # Fallback to /proc/cpuinfo
        DETECTED_CPU="$(awk -F: '/model name/{print $2; exit}' /proc/cpuinfo | xargs || true)"
        [ -z "$DETECTED_CPU" ] && DETECTED_CPU="$(uname -m)"
    fi

    # GPU (prefer lspci)
    if command -v lspci >/dev/null 2>&1; then
        # pick first VGA or 3D controller entry
        DETECTED_GPU="$(lspci 2>/dev/null | grep -E 'VGA|3D' | head -n1 | sed -E 's/^.*: //; s/\\s*\\[.*\\]$//' | xargs || true)"
    else
        # Use glxinfo if available
        if command -v glxinfo >/dev/null 2>&1; then
            DETECTED_GPU="$(glxinfo -B 2>/dev/null | awk -F: '/Device:/ {print $2; exit}' | xargs || true)"
        else
            DETECTED_GPU="Unknown"
        fi
    fi
    [ -z "$DETECTED_GPU" ] && DETECTED_GPU="Unknown"

    # RAM (human friendly)
    if command -v free >/dev/null 2>&1; then
        DETECTED_RAM="$(free -h | awk '/Mem:/ {print $2}' | xargs || true)"
    else
        # Fallback to /proc/meminfo in KB -> convert to MiB
        memkb="$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo || true)"
        if [ -n "$memkb" ]; then
            DETECTED_RAM="$(awk -v kb="$memkb" 'BEGIN{ printf \"%.0fM\", kb/1024 }')"
        else
            DETECTED_RAM="Unknown"
        fi
    fi

    # Expose short CPU vendor detection
    CPU_VENDOR="$(awk -F: '/^vendor_id/ {print $2; exit}' /proc/cpuinfo || true)"
    [ -z "$CPU_VENDOR" ] && CPU_VENDOR="$(awk -F: '/^vendor_id/ {print $2; exit}' /proc/cpuinfo || true)"
    CPU_VENDOR="${CPU_VENDOR:-Unknown}"

    # Provide global variables for other scripts
    export DETECTED_OS DETECTED_CPU DETECTED_GPU DETECTED_RAM CPU_VENDOR
}

# Display detected system information to user
show_system_info() {
    # Print system information in the same style as other headers
    detect_system_info

    if supports_gum; then
        display_info "Detected OS: $DETECTED_OS"
        display_info "Detected DE: ${XDG_CURRENT_DESKTOP:-None}"
        display_info "Detected CPU: ${DETECTED_CPU:-Unknown}"
        display_info "Detected GPU: ${DETECTED_GPU:-Unknown}"
        display_info "Detected RAM: ${DETECTED_RAM:-Unknown}"
    else
        display_info "System Detection Results:" "OS: ${DETECTED_OS:-Unknown}\nDE: ${XDG_CURRENT_DESKTOP:-None}\nCPU: ${DETECTED_CPU:-Unknown}\nGPU: ${DETECTED_GPU:-Unknown}\nRAM: ${DETECTED_RAM:-Unknown}"
    fi
}

# -----------------------------------------------------------------------------
# Power management configuration
# -----------------------------------------------------------------------------

# Helper function to attempt package installation with fallbacks
_try_install() {
    # Args: package1 [package2 ...]
    for pkg in "$@"; do
        if [ -z "$pkg" ]; then
            continue
        fi
        if command -v install_pkg >/dev/null 2>&1; then
            install_packages_with_progress "$pkg" && return 0
        else
            # Fallback: try package manager generic installs (best-effort)
            if [ "${DRY_RUN:-false}" = "true" ]; then
                display_info "[DRY-RUN] Would install $pkg"
                return 0
            fi
            display_progress "installing" "$pkg"
            if command -v apt-get >/dev/null 2>&1; then
                apt-get install -y "$pkg" >/dev/null 2>&1 && display_success "✓ $pkg installed" && return 0
            elif command -v dnf >/dev/null 2>&1; then
                dnf install -y "$pkg" >/dev/null 2>&1 && display_success "✓ $pkg installed" && return 0
            elif command -v pacman >/dev/null 2>&1; then
                pacman -S --noconfirm "$pkg" >/dev/null 2>&1 && display_success "✓ $pkg installed" && return 0
            fi
            display_error "✗ Failed to install $pkg"
        fi
    done
    return 1
}

# Configure power management (power-profiles-daemon, cpupower, or tuned)
configure_power_management() {
    step "Configuring Power Management"

    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would detect and configure power management utilities (power-profiles-daemon/cpupower/tuned)"
        return 0
    fi

    # 1) Prefer power-profiles-daemon (modern desktops)
    if command -v powerprofilesctl >/dev/null 2>&1; then
        log_info "power-profiles-daemon detected"
        if systemctl enable --now power-profiles-daemon >/dev/null 2>&1; then
            log_success "power-profiles-daemon enabled"
        else
            log_warn "Failed to enable power-profiles-daemon service"
        fi

        # Set sensible default profile; use performance for gaming mode if requested
        if [ "${INSTALL_GAMING:-false}" = "true" ]; then
            if powerprofilesctl set performance >/dev/null 2>&1; then
                log_success "power-profiles-daemon profile set to 'performance'"
            fi
        else
            if powerprofilesctl set balanced >/dev/null 2>&1; then
                log_success "power-profiles-daemon profile set to 'balanced'"
            fi
        fi
        return 0
    fi

    # Try to install power-profiles-daemon first (user preference)
    if _try_install power-profiles-daemon; then
        if command -v powerprofilesctl >/dev/null 2>&1; then
            log_success "power-profiles-daemon installed"
            if systemctl enable --now power-profiles-daemon >/dev/null 2>&1; then
                log_success "power-profiles-daemon enabled"
            fi
            # Configure default profile
            if [ "${INSTALL_GAMING:-false}" = "true" ]; then
                powerprofilesctl set performance >/dev/null 2>&1 || true
            else
                powerprofilesctl set balanced >/dev/null 2>&1 || true
            fi
            return 0
        fi
    else
        log_info "power-profiles-daemon package not available or install failed; falling back"
    fi

    # 2) If cpufreq exists on this system, prefer cpupower (governor etc.)
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ] || grep -q -i 'cpufreq' /proc/cpuinfo 2>/dev/null; then
        log_info "cpufreq subsystem detected; attempting cpupower install"
        # Try common package names in order
        if _try_install cpupower linux-cpupower cpufrequtils; then
            # enable cpupower if supported
            if systemctl enable --now cpupower >/dev/null 2>&1 || systemctl enable --now cpupower.service >/dev/null 2>&1; then
                log_success "cpupower enabled"
            else
                log_warn "cpupower installed but enabling service failed or service not provided by package"
            fi

            # Try to set governor to performance for gaming
            if command -v cpupower >/dev/null 2>&1; then
                if [ "${INSTALL_GAMING:-false}" = "true" ]; then
                    cpupower frequency-set -g performance >/dev/null 2>&1 || true
                fi
            fi
            return 0
        else
            log_info "cpupower not available; falling back to tuned"
        fi
    else
        log_info "cpufreq subsystem not found; skipping cpupower"
    fi

    # 3) Fallback to tuned (legacy / older systems)
    if command -v tuned-adm >/dev/null 2>&1; then
        log_info "tuned already installed"
        if systemctl enable --now tuned >/dev/null 2>&1; then
            log_success "tuned enabled"
            return 0
        fi
    fi

    if _try_install tuned; then
        if systemctl enable --now tuned >/dev/null 2>&1; then
            log_success "tuned installed and enabled"
            return 0
        else
            log_warn "tuned installed but could not enable service"
            return 0
        fi
    fi

    log_warn "No suitable power management tool was installed. You can try installing 'power-profiles-daemon', 'cpupower' or 'tuned' manually."
    return 1
}

# Export the main helpers so the installer can call them if the file is sourced.
export -f detect_system_info
export -f show_system_info
export -f configure_power_management
