#!/bin/bash
set -uo pipefail

# =============================================================================
# wakeonlan_config.sh
#
# LinuxInstaller module to configure and persist Wake-on-LAN (WoL) across
# wired Ethernet interfaces on multiple distributions.
#
# Features:
# - Detect wired NICs (prefers NetworkManager device info when available)
# - Ensure ethtool is installed (uses distro package manager via install_pkg)
# - Enable WoL at runtime and persist it:
#     - Prefer NetworkManager connection property (802-3-ethernet.wake-on-lan=magic)
#     - Otherwise create per-interface systemd oneshot service to apply WoL on boot
# - Idempotent and respects DRY_RUN mode
# - Exposes function `wakeonlan_main_config` which linuxinstaller can call
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load common helpers and distro detection (required for install_pkg, logging, state)
if [ -f "$SCRIPT_DIR/common.sh" ]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/common.sh"
fi
if [ -f "$SCRIPT_DIR/distro_check.sh" ]; then
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/distro_check.sh"
fi

# ---------------------------
# Helpers
# ---------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Return newline-separated list of candidate wired interfaces
# - Prefer predictable NM device list when available
# - Fallback to kernel interface names, filtering virtual/wireless interfaces
detect_wired_interfaces() {
    local dev
    local seen=()
    # Prefer NetworkManager device list if available
    if command_exists nmcli; then
        # format: DEVICE:TYPE
        while IFS=: read -r dev type; do
            if [ "$type" = "ethernet" ]; then
                seen+=("$dev")
            fi
        done < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null || true)
    fi

    # Fallback scanning
    if [ ${#seen[@]} -eq 0 ]; then
        while IFS= read -r dev; do
            case "$dev" in
                lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|wl*|wlan*) continue ;;
            esac
            # Only consider if sysfs device exists (physical/real device)
            [ -d "/sys/class/net/$dev/device" ] || continue
            seen+=("$dev")
        done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' || true)
    fi

    # Unique and print
    printf "%s\n" "${seen[@]}" | awk '!x[$0]++' | sed '/^$/d'
}

# Ensure ethtool is installed; respects DRY_RUN
wakeonlan_install_ethtool() {
    if command_exists ethtool; then
        log_info "ethtool already available"
        return 0
    fi

    log_info "ethtool not found; attempting to install"
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would install 'ethtool' via package manager"
        return 0
    fi

    # Use the install_pkg wrapper (defined in common.sh) to install in a distro-agnostic way
    if command_exists install_pkg; then
        install_pkg ethtool || {
            log_warn "install_pkg failed to install 'ethtool'. WoL actions may fail."
            return 1
        }
    else
        # Fallback: try common package managers
        if command_exists pacman; then
            sudo pacman -S --noconfirm --needed ethtool >> "$INSTALL_LOG" 2>&1 || true
        elif command_exists apt-get; then
            sudo apt-get update -y >> "$INSTALL_LOG" 2>&1 || true
            sudo apt-get install -y ethtool >> "$INSTALL_LOG" 2>&1 || true
        elif command_exists dnf; then
            sudo dnf install -y ethtool >> "$INSTALL_LOG" 2>&1 || true
        else
            log_warn "No known package manager wrapper available and 'install_pkg' not present. Please install 'ethtool' manually."
            return 1
        fi
    fi

    if ! command_exists ethtool; then
        log_warn "ethtool still not available after install attempts"
        return 1
    fi

    log_success "ethtool is available"
    return 0
}

# Test if an interface supports Wake-on-LAN before attempting configuration
wakeonlan_supports_wol() {
    local iface="$1"

    # Test if interface supports Wake-on-LAN
    local wol_support
    wol_support=$(sudo ethtool "$iface" 2>/dev/null | awk '/Wake-on:/ {print $2}')

    # If ethtool couldn't get Wake-on info, assume not supported
    if [ -z "$wol_support" ]; then
        log_info "Unable to determine Wake-on-LAN support for $iface"
        return 1
    fi

    # Check if WoL can be enabled (has g or d option)
    # g = enabled, d = disabled, no WoL support reported
    if [[ "$wol_support" != *"g"* && "$wol_support" != *"d"* ]]; then
        log_info "Interface $iface does not support Wake-on-LAN or is not suitable"
        return 1
    fi

    return 0
}

# Create systemd oneshot service to assert WoL on boot for given interface
wakeonlan_create_systemd_service() {
    local iface="$1"
    local safe_iface
    safe_iface="$(printf '%s' "$iface" | sed 's/[^A-Za-z0-9_-]/_/g')"
    local svc_file="/etc/systemd/system/wol-${safe_iface}.service"
    local ethtool_bin
    ethtool_bin="$(command -v ethtool || echo /sbin/ethtool)"

    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would create systemd unit $svc_file (ExecStart: $ethtool_bin -s $iface wol g)"
        return 0
    fi

    sudo tee "$svc_file" > /dev/null <<EOF
[Unit]
Description=Enable Wake-on-LAN for $iface
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$ethtool_bin -s $iface wol g
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload >> "$INSTALL_LOG" 2>&1 || true
    sudo systemctl enable --now "wol-${safe_iface}.service" >> "$INSTALL_LOG" 2>&1 || sudo systemctl start "wol-${safe_iface}.service" >> "$INSTALL_LOG" 2>&1 || true
    log_success "Created and enabled systemd service for $iface"
}

# Persist Wake-on-LAN via NetworkManager for a device, if possible
wakeonlan_persist_via_nm() {
    local iface="$1"
    if ! command_exists nmcli; then
        return 1
    fi

    # find connection(s) associated with device
    local conn
    # name:device
    while IFS=: read -r name dev; do
        if [ "$dev" = "$iface" ]; then
            conn="$name"
            break
        fi
    done < <(nmcli -t -f NAME,DEVICE connection show 2>/dev/null || true)

    if [ -z "$conn" ]; then
        log_info "No NetworkManager connection found for $iface"
        return 1
    fi

    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would set NM connection '$conn' 802-3-ethernet.wake-on-lan=magic"
        return 0
    fi

    if sudo nmcli connection modify "$conn" 802-3-ethernet.wake-on-lan magic >> "$INSTALL_LOG" 2>&1; then
        log_success "Set NetworkManager connection '$conn' wake-on-lan=magic"
        # try to reapply to ensure immediate effect
        sudo nmcli connection down "$conn" >> "$INSTALL_LOG" 2>&1 || true
        sudo nmcli connection up "$conn" >> "$INSTALL_LOG" 2>&1 || true
        return 0
    else
        log_warn "Failed to set wake-on-lan for NM connection '$conn' (see $INSTALL_LOG)"
        return 1
    fi
}

# Enable WoL on a single interface (runtime + persistence)
wakeonlan_enable_iface() {
    local iface="$1"

    # Check if interface supports Wake-on-LAN before attempting configuration
    if ! wakeonlan_supports_wol "$iface"; then
        log_info "Interface $iface does not support Wake-on-LAN or cannot be configured. Skipping."
        return 1
    fi

    # Runtime enablement
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would run: ethtool -s $iface wol g"
    else
        if sudo ethtool -s "$iface" wol g >> "$INSTALL_LOG" 2>&1; then
            log_success "Enabled Wake-on-LAN (runtime) on $iface"
        else
            log_warn "Failed to enable Wake-on-LAN (runtime) on $iface. This may be normal for some virtual/wireless interfaces."
        fi
    fi

    # Persistence: try NetworkManager first, then systemd unit fallback
    if wakeonlan_persist_via_nm "$iface"; then
        return 0
    fi

    wakeonlan_create_systemd_service "$iface"
}

# Disable WoL on a single interface (runtime + persistence cleanup)
wakeonlan_disable_iface() {
    local iface="$1"
    local safe_iface
    safe_iface="$(printf '%s' "$iface" | sed 's/[^A-Za-z0-9_-]/_/g')"
    local svc_file="/etc/systemd/system/wol-${safe_iface}.service"

    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would run: ethtool -s $iface wol d"
    else
        sudo ethtool -s "$iface" wol d >> "$INSTALL_LOG" 2>&1 || true
        log_info "Attempted to disable WoL runtime setting on $iface"
    fi

    # Try to remove NM config if present
    if command_exists nmcli; then
        # find matching connection(s)
        while IFS=: read -r name dev; do
            if [ "$dev" = "$iface" ]; then
                if [ "${DRY_RUN:-false}" = "true" ]; then
                    log_info "[DRY-RUN] Would reset wake-on-lan for NM connection '$name'"
                else
                    sudo nmcli connection modify "$name" 802-3-ethernet.wake-on-lan default >> "$INSTALL_LOG" 2>&1 || sudo nmcli connection modify "$name" 802-3-ethernet.wake-on-lan "" >> "$INSTALL_LOG" 2>&1 || true
                    log_info "Reset NetworkManager wake-on-lan for '$name'"
                fi
            fi
        done < <(nmcli -t -f NAME,DEVICE connection show 2>/dev/null || true)
    fi

    # Remove systemd service if present
    if [ -f "$svc_file" ]; then
        if [ "${DRY_RUN:-false}" = "true" ]; then
            log_info "[DRY-RUN] Would remove $svc_file and disable service"
        else
            sudo systemctl disable --now "wol-${safe_iface}.service" >> "$INSTALL_LOG" 2>&1 || true
            sudo rm -f "$svc_file"
            sudo systemctl daemon-reload >> "$INSTALL_LOG" 2>&1 || true
            log_success "Removed systemd service for $iface"
        fi
    fi
}

# Summarize WoL status for wired interfaces
wakeonlan_status() {
    local iface
    local any=0
    while IFS= read -r iface; do
        any=1
        if command_exists ethtool; then
            local mac wol
            mac="$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo 'unknown')"
            wol="$(ethtool "$iface" 2>/dev/null | awk '/Wake-on/ {print $2}' || true)"
            if [ -z "$wol" ]; then
                log_warn "$iface: unable to determine Wake-on (ethtool output missing)"
            elif [[ "$wol" == *g* || "$wol" == *G* ]]; then
                log_success "$iface: WoL ENABLED (g) - MAC: $mac"
            else
                log_warn "$iface: WoL not enabled (current: $wol) - MAC: $mac"
            fi
        else
            log_warn "$iface: ethtool not installed; cannot determine WoL status. MAC: $(cat "/sys/class/net/$iface/address" 2>/dev/null || echo 'unknown')"
        fi
        # Persistence hints
        if command_exists nmcli; then
            local conn
            conn="$(nmcli -t -f NAME,DEVICE connection show 2>/dev/null | awk -F: -v d="$iface" '$2==d{print $1}')" || true
            if [ -n "$conn" ]; then
                local nmv
                nmv="$(nmcli -g 802-3-ethernet.wake-on-lan connection show "$conn" 2>/dev/null || echo 'not set')"
                log_info "   Persisted (NetworkManager): $conn -> ${nmv:-not set}"
            fi
        fi
        local safe_iface
        safe_iface="$(printf '%s' "$iface" | sed 's/[^A-Za-z0-9_-]/_/g')"
        if [ -f "/etc/systemd/system/wol-${safe_iface}.service" ]; then
            log_info "   Persisted (systemd): wol-${safe_iface}.service present"
        fi
    done < <(detect_wired_interfaces)

    if [ "$any" -eq 0 ]; then
        log_warn "No candidate wired interfaces detected to query WoL status"
    fi
}

# ---------------------------
# Top-level operations (to be called by linuxinstaller)
# ---------------------------

# Enable WoL on all detected wired interfaces (idempotent)
wakeonlan_enable_all() {
    step "Configuring Wake-on-LAN for wired interfaces"
    CURRENT_STEP_MESSAGE="Configuring Wake-on-LAN for wired interfaces"

    # Try to ensure we can run runtime commands
    wakeonlan_install_ethtool || log_warn "ethtool installation/check failed; continuing but operations may fail."

    local devs=()
    mapfile -t devs < <(detect_wired_interfaces)

    if [ ${#devs[@]} -eq 0 ]; then
        log_warn "No wired Ethernet interfaces detected; skipping Wake-on-LAN configuration"
        mark_step_complete "wakeonlan_setup"
        return 0
    fi

    local cnt=0
    local success_count=0

    for iface in "${devs[@]}"; do
        log_info "Processing interface: $iface"
        if wakeonlan_enable_iface "$iface"; then
            success_count=$((success_count + 1))
        fi
        cnt=$((cnt + 1))
    done

    if [ $success_count -gt 0 ]; then
        log_success "Configured Wake-on-LAN on $success_count interface(s) out of $cnt attempted"
        mark_step_complete "wakeonlan_setup"
    else
        log_warn "No suitable interfaces found for Wake-on-LAN configuration"
        log_info "Wake-on-LAN may not be supported on virtual/wireless interfaces"
        mark_step_complete "wakeonlan_setup"
    fi
}

# Disable WoL on all detected wired interfaces and remove persistence
wakeonlan_disable_all() {
    step "Disabling Wake-on-LAN for wired interfaces"
    CURRENT_STEP_MESSAGE="Disabling Wake-on-LAN for wired interfaces"

    local devs
    mapfile -t devs < <(detect_wired_interfaces)

    if [ ${#devs[@]} -eq 0 ]; then
        log_warn "No wired interfaces detected; nothing to disable"
        mark_step_complete "wakeonlan_disable"
        return 0
    fi

    for iface in "${devs[@]}"; do
        wakeonlan_disable_iface "$iface"
    done

    log_success "Disabled Wake-on-LAN for detected wired interfaces"
    mark_step_complete "wakeonlan_disable"
}

# Show WoL status (non-invasive)
wakeonlan_show_status() {
    step "Wake-on-LAN status"
    CURRENT_STEP_MESSAGE="Checked Wake-on-LAN status"
    wakeonlan_status
    mark_step_complete "wakeonlan_status"
}

# Public entrypoint for linuxinstaller
# Call this function (e.g. from install flow) to enable WoL automatically
wakeonlan_main_config() {
    # Avoid re-running if already completed
    if is_step_complete "wakeonlan_setup"; then
        log_info "Wake-on-LAN already configured; skipping"
        return 0
    fi

    wakeonlan_enable_all
}

# Optional: helper to expose a single command interface when the module is executed directly
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Minimal CLI for quick testing; prefer non-interactive operations
    case "${1:-}" in
        enable|--enable|--auto) wakeonlan_enable_all ;;
        disable|--disable) wakeonlan_disable_all ;;
        status|--status) wakeonlan_show_status ;;
        *) echo "Usage: $0 {enable|disable|status}" ; exit 2 ;;
    esac
fi

# Export public functions
export -f wakeonlan_main_config
export -f wakeonlan_enable_all
export -f wakeonlan_disable_all
export -f wakeonlan_show_status
