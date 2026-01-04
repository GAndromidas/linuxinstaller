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

# Check if interface is definitely a wireless/WiFi interface
is_wifi_interface() {
    local iface="$1"
    
    # Method 1: Check for wireless directory (most reliable)
    if [ -d "/sys/class/net/$iface/wireless" ]; then
        return 0
    fi
    
    # Method 2: Check interface name patterns for WiFi
    if [[ "$iface" =~ ^(wl|wlan|wifi|wlp) ]]; then
        return 0
    fi
    
    # Method 3: Check if it's a wireless device via uevent
    if [ -f "/sys/class/net/$iface/device/uevent" ]; then
        if grep -qi "wifi\|wlan\|wireless" "/sys/class/net/$iface/device/uevent" 2>/dev/null; then
            return 0
        fi
    fi
    
    # Method 4: Check driver type
    if [ -d "/sys/class/net/$iface/device/driver" ]; then
        local driver_path="/sys/class/net/$iface/device/driver"
        local driver_name=$(basename "$(readlink "$driver_path" 2>/dev/null)" 2>/dev/null || echo "")
        case "$driver_name" in
            *wifi*|*wlan*|*ath*|*rtw*|*brcm*|*iwl*|*rtlwifi*) return 0 ;;
        esac
    fi
    
    # Method 5: Use iwconfig if available (legacy but reliable)
    if command -v iwconfig >/dev/null 2>&1; then
        if iwconfig "$iface" 2>/dev/null | grep -q "no wireless extensions\|IEEE 802.11"; then
            # If it has wireless extensions or mentions 802.11, it's wireless
            if ! iwconfig "$iface" 2>/dev/null | grep -q "no wireless extensions"; then
                return 0
            fi
        fi
    fi
    
    return 1
}

# Check if interface is virtual (should be excluded)
is_virtual_interface() {
    local iface="$1"
    
    # Check if it has no physical device
    if [ ! -d "/sys/class/net/$iface/device" ]; then
        return 0
    fi
    
    # Check virtual interface patterns
    case "$iface" in
        lo|docker*|veth*|br-*|virbr*|tun*|tap*|wg*|vnet*|bond*|team*|dummy*) return 0 ;;
    esac
    
    # Check if it's a bridge or tunnel
    if [ -f "/sys/class/net/$iface/bridge" ] || [ -f "/sys/class/net/$iface/tun_flags" ]; then
        return 0
    fi
    
    # Check if device is virtual via uevent
    if [ -f "/sys/class/net/$iface/device/uevent" ]; then
        if grep -qi "virtual\|bridge\|tunnel" "/sys/class/net/$iface/device/uevent" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

# Check if interface is definitely a wired LAN interface
is_lan_interface() {
    local iface="$1"
    
    # Must exist
    if [ ! -d "/sys/class/net/$iface" ]; then
        return 1
    fi
    
    # Must not be WiFi
    if is_wifi_interface "$iface"; then
        return 1
    fi
    
    # Must not be virtual
    if is_virtual_interface "$iface"; then
        return 1
    fi
    
    # Must have typical wired interface naming or characteristics
    # Ethernet interfaces typically follow these patterns:
    if [[ "$iface" =~ ^(en|eth|lan) ]]; then
        return 0
    fi
    
    # Additional check: if it's a physical device and not WiFi, assume it's wired
    if [ -d "/sys/class/net/$iface/device" ] && [ ! -d "/sys/class/net/$iface/wireless" ]; then
        # Check if it's a PCI or USB device (typical for wired NICs)
        if [ -d "/sys/class/net/$iface/device/subsystem" ]; then
            local subsystem=$(basename "$(readlink "/sys/class/net/$iface/device/subsystem" 2>/dev/null)" 2>/dev/null || echo "")
            case "$subsystem" in
                pci|usb|platform) return 0 ;;
            esac
        fi
    fi
    
    return 1
}

# Return newline-separated list of wired LAN interfaces only
# - Smart detection that excludes WiFi, virtual, and wireless interfaces
detect_wired_interfaces() {
    local lan_interfaces=()
    
    # Get all network interfaces
    local all_interfaces=()
    while IFS= read -r iface; do
        # Skip empty lines
        [ -n "$iface" ] && all_interfaces+=("$iface")
    done < <(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' || true)
    
    # Also check /sys/class/net for completeness
    while IFS= read -r iface; do
        # Skip if already in list
        if [[ " ${all_interfaces[*]} " =~ " $iface " ]]; then
            continue
        fi
        [ -n "$iface" ] && all_interfaces+=("$iface")
    done < <(ls /sys/class/net/ 2>/dev/null || true)
    
    # Filter for LAN interfaces only
    for iface in "${all_interfaces[@]}"; do
        if is_lan_interface "$iface"; then
            lan_interfaces+=("$iface")
        fi
    done
    
    # Remove duplicates and sort
    printf "%s\n" "${lan_interfaces[@]}" | awk '!x[$0]++' | sort
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

# Interactive prompt for Wake-on-LAN configuration
wakeonlan_prompt_configuration() {
    # Only prompt if we have wired interfaces that support WoL
    local devs=()
    mapfile -t devs < <(detect_wired_interfaces)
    
    if [ ${#devs[@]} -eq 0 ]; then
        log_info "No wired Ethernet interfaces detected; skipping Wake-on-LAN configuration"
        export INSTALL_WAKEONLAN=false
        return 1
    fi
    
    # Check if any interfaces support WoL
    local supported_devs=()
    for iface in "${devs[@]}"; do
        if wakeonlan_supports_wol "$iface"; then
            supported_devs+=("$iface")
        fi
    done
    
    if [ ${#supported_devs[@]} -eq 0 ]; then
        log_info "No wired interfaces support Wake-on-LAN; skipping configuration"
        export INSTALL_WAKEONLAN=false
        return 1
    fi
    
    # Interactive prompt using gum if available
    if supports_gum; then
        echo ""
        display_box "🌐 Wake-on-LAN Configuration" "Wake-on-LAN allows you to power on your computer remotely over the network.\n\nThis is useful for:\n• Remote access to desktop computers\n• Server management\n• Home automation integration\n\nDetected compatible interfaces: ${supported_devs[*]}"
        display_warning "Note: Wake-on-LAN requires wired Ethernet and BIOS/UEFI support"
        
        if gum confirm "Enable Wake-on-LAN for detected interfaces?" --default=false; then
            export INSTALL_WAKEONLAN=true
            display_success "✓ Wake-on-LAN will be configured for: ${supported_devs[*]}"
        else
            export INSTALL_WAKEONLAN=false
            display_info "○ Skipping Wake-on-LAN configuration"
            echo ""
            return 1
        fi
    else
        # Fallback text-based prompt
        echo ""
        echo "Wake-on-LAN Configuration"
        echo "========================"
        echo "Wake-on-LAN allows you to power on your computer remotely over the network."
        echo ""
        echo "Compatible interfaces detected: ${supported_devs[*]}"
        echo ""
        local attempts=0
        while [ $attempts -lt 3 ]; do
            attempts=$((attempts + 1))
            read -r -p "Enable Wake-on-LAN? (y/N): " choice 2>/dev/null || {
                echo "Input not available, skipping Wake-on-LAN configuration"
                export INSTALL_WAKEONLAN=false
                return 1
            }
            
            case "$(echo "$choice" | tr '[:upper:]' '[:lower:]')" in
                y|yes)
                    export INSTALL_WAKEONLAN=true
                    echo "✓ Wake-on-LAN will be configured for: ${supported_devs[*]}"
                    break ;;
                n|no|"")
                    export INSTALL_WAKEONLAN=false
                    echo "○ Skipping Wake-on-LAN configuration"
                    echo ""
                    return 1 ;;
                *)
                    if [ $attempts -eq 3 ]; then
                        echo "Too many invalid attempts. Skipping Wake-on-LAN configuration."
                        export INSTALL_WAKEONLAN=false
                        return 1
                    else
                        echo "Please enter 'y' for yes or 'n' for no."
                    fi ;;
            esac
        done
    fi
    
    return 0
}

# Public entrypoint for linuxinstaller
# Call this function (e.g. from install flow) to enable WoL automatically
wakeonlan_main_config() {
    log_info "Starting Wake-on-LAN configuration..."
    
    # Interactive prompt for Wake-on-LAN configuration
    if wakeonlan_prompt_configuration; then
        wakeonlan_enable_all
        wakeonlan_show_info
    else
        # User declined or no compatible interfaces
        if [ "${INSTALL_WAKEONLAN:-false}" = "false" ]; then
            if supports_gum; then
                display_info "○ Wake-on-LAN not enabled"
            else
                log_info "Wake-on-LAN configuration skipped"
            fi
        fi
    fi
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
export -f wakeonlan_prompt_configuration
export -f is_wifi_interface
export -f is_virtual_interface
export -f is_lan_interface
export -f detect_wired_interfaces
export -f wakeonlan_enable_all
export -f wakeonlan_disable_all
export -f wakeonlan_show_status
export -f wakeonlan_show_info
