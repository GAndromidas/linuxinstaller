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

# command_exists() function - fallback if common.sh not loaded
if ! command -v command_exists >/dev/null 2>&1; then
    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }
fi

# Return newline-separated list of candidate wired interfaces
# - Detect all ethernet adapters in any system (like reference wakeonlan.sh)
detect_wired_interfaces() {
    local eth_interfaces=()

    # Method 1: Check for common specific interfaces first (like reference script)
    local common_interfaces=("enp3s0" "enp5s0" "enp1s0" "enp2s0" "enp4s0" "enp6s0" "enp7s0" "enp8s0" "enp9s0" "eth0" "eth1" "eth2")
    for iface in "${common_interfaces[@]}"; do
        if ip link show "$iface" &>/dev/null; then
            # Verify it's not wireless and has a physical device
            if [ -d "/sys/class/net/$iface/device" ] && [ ! -d "/sys/class/net/$iface/wireless" ]; then
                eth_interfaces+=("$iface")
            fi
        fi
    done

    # Method 2: Scan for any interface starting with 'enp' or 'eth' (comprehensive scan)
    while IFS= read -r iface; do
        # Skip if already found in common interfaces
        if [[ " ${eth_interfaces[*]} " =~ " $iface " ]]; then
            continue
        fi

        # Check if it's an ethernet interface (enp* or eth*)
        if [[ "$iface" =~ ^(enp|eth) ]]; then
            # Verify it's not wireless and has a physical device
            if [ -d "/sys/class/net/$iface/device" ] && [ ! -d "/sys/class/net/$iface/wireless" ]; then
                # Additional check: make sure it's not a virtual interface
                case "$iface" in
                    lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|wl*|wlan*) continue ;;
                esac
                eth_interfaces+=("$iface")
            fi
        fi
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' || true)

    # Method 3: Fallback to NetworkManager device list if available and we found nothing
    if [ ${#eth_interfaces[@]} -eq 0 ] && command_exists nmcli; then
        while IFS=: read -r dev type; do
            if [ "$type" = "ethernet" ]; then
                # Verify it's not wireless
                if [ ! -d "/sys/class/net/$dev/wireless" ]; then
                    eth_interfaces+=("$dev")
                fi
            fi
        done < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null || true)
    fi

    # Remove duplicates and print
    printf "%s\n" "${eth_interfaces[@]}" | awk '!x[$0]++' | sed '/^$/d'
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

    # Try to install ethtool using available package managers
    local installed=false
    if command_exists pacman; then
        if pacman -S --noconfirm --needed ethtool >/dev/null 2>&1; then
            installed=true
        fi
    elif command_exists apt-get; then
        if apt-get update -qq >/dev/null 2>&1 && apt-get install -y ethtool >/dev/null 2>&1; then
            installed=true
        fi
    elif command_exists dnf; then
        if dnf install -y ethtool >/dev/null 2>&1; then
            installed=true
        fi
    fi

    if [ "$installed" = false ]; then
        log_warn "Failed to install 'ethtool'. WoL actions may fail."
        return 1
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
    wol_support=$(ethtool "$iface" 2>/dev/null | awk '/Wake-on:/ {print $2}')

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

    tee "$svc_file" > /dev/null <<EOF
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

    systemctl daemon-reload || true
    systemctl enable --now "wol-${safe_iface}.service" || systemctl start "wol-${safe_iface}.service" || true
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

    if nmcli connection modify "$conn" 802-3-ethernet.wake-on-lan magic; then
        log_success "Set NetworkManager connection '$conn' wake-on-lan=magic"
        # try to reapply to ensure immediate effect
        nmcli connection down "$conn" || true
        nmcli connection up "$conn" || true
        return 0
    else
        log_warn "Failed to set wake-on-lan for NM connection '$conn'"
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
        if ethtool -s "$iface" wol g; then
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
        ethtool -s "$iface" wol d || true
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
                    nmcli connection modify "$name" 802-3-ethernet.wake-on-lan default || nmcli connection modify "$name" 802-3-ethernet.wake-on-lan "" || true
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
            systemctl disable --now "wol-${safe_iface}.service" || true
            rm -f "$svc_file"
            systemctl daemon-reload || true
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
    display_step "🌐" "Configuring Wake-on-LAN for wired interfaces"

    # Try to ensure we can run runtime commands
    wakeonlan_install_ethtool || log_warn "ethtool installation/check failed; continuing but operations may fail."

    local devs=()
    mapfile -t devs < <(detect_wired_interfaces)

    if [ ${#devs[@]} -eq 0 ]; then
        log_warn "No wired Ethernet interfaces detected; skipping Wake-on-LAN configuration"
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
    else
        log_warn "No suitable interfaces found for Wake-on-LAN configuration"
        log_info "Wake-on-LAN may not be supported on virtual/wireless interfaces"
    fi
}

# Disable WoL on all detected wired interfaces and remove persistence
wakeonlan_disable_all() {
    display_step "🌐" "Disabling Wake-on-LAN for wired interfaces"

    local devs
    mapfile -t devs < <(detect_wired_interfaces)

    if [ ${#devs[@]} -eq 0 ]; then
        log_warn "No wired interfaces detected; nothing to disable"
        return 0
    fi

    for iface in "${devs[@]}"; do
        wakeonlan_disable_iface "$iface"
    done

    log_success "Disabled Wake-on-LAN for detected wired interfaces"
}

# Show WoL status (non-invasive)
wakeonlan_show_status() {
    display_step "📊" "Wake-on-LAN status"
    wakeonlan_status
}

# Show WoL status and MAC addresses for all configured interfaces
wakeonlan_show_info() {
    log_info "Wake-on-LAN configuration completed"
    log_info "MAC addresses for ethernet interfaces:"

    local devs=()
    mapfile -t devs < <(detect_wired_interfaces)

    for iface in "${devs[@]}"; do
        local mac=""
        if [ -r "/sys/class/net/$iface/address" ]; then
            mac=$(cat "/sys/class/net/$iface/address")
        else
            mac="unknown"
        fi
        log_info "  $iface: $mac"
    done

    log_info "Use 'ethtool <interface>' to check Wake-on-LAN status"
    log_info "Use 'wol <mac>' from another machine to wake this system"
}

# Public entrypoint for linuxinstaller
# Call this function (e.g. from install flow) to enable WoL automatically
wakeonlan_main_config() {
    wakeonlan_enable_all
    wakeonlan_show_info
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
export -f wakeonlan_show_info
