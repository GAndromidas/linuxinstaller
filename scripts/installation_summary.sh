#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Show comprehensive installation summary with beautiful formatting (cross-distro compatible)
show_installation_summary() {
    step "Final Installation Summary"

    # Gather system information dynamically for all distros
    local os_info=""
    local kernel_info=""
    local desktop_info=""
    local cpu_info=""
    local gpu_info=""
    local ram_info=""

    # Cross-distro OS detection
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_info="${PRETTY_NAME:-${NAME:-Unknown}}"
    elif [ -f /etc/redhat-release ]; then
        os_info=$(cat /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        os_info="Debian $(cat /etc/debian_version)"
    else
        os_info=$(uname -s)
    fi

    # Kernel information
    kernel_info=$(uname -r)

    # Desktop environment
    desktop_info="${XDG_CURRENT_DESKTOP:-None}"
    case "$desktop_info" in
        *"KDE"*) desktop_info="KDE Plasma" ;;
        *"GNOME"*) desktop_info="GNOME" ;;
        *"XFCE"*) desktop_info="XFCE" ;;
        *"LXQT"*) desktop_info="LXQt" ;;
        *"CINNAMON"*) desktop_info="Cinnamon" ;;
        *"MATE"*) desktop_info="MATE" ;;
        *"BUDGIE"*) desktop_info="Budgie" ;;
        "") desktop_info="None (Server mode)" ;;
    esac

    # CPU information
    if command -v lscpu >/dev/null 2>&1; then
        cpu_info=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//' | head -1)
    else
        cpu_info=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^\s*//')
    fi

    # GPU information (simplified)
    if command -v lspci >/dev/null 2>&1; then
        gpu_info=$(lspci | grep -i vga | head -1 | cut -d: -f3- | sed 's/^\s*//')
    else
        gpu_info="Unknown"
    fi

    # RAM information
    if [ -f /proc/meminfo ]; then
        ram_kb=$(grep "MemTotal:" /proc/meminfo | awk '{print $2}')
        ram_gb=$((ram_kb / 1024 / 1024))
        ram_info="${ram_gb}GB"
    else
        ram_info="Unknown"
    fi

    # Display system information with beautiful formatting
    if supports_gum; then
        gum style --margin "1 2" --foreground "$GUM_PRIMARY_FG" --bold "╔══════════════════════════════════════════════════════════╗"
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "║                System Information                      ║"
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "╚══════════════════════════════════════════════════════════╝"
        echo ""

        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🖥️  Operating System: $os_info"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🧠 Kernel Version: $kernel_info"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🖼️  Desktop Environment: $desktop_info"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "⚡ CPU: $cpu_info"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🎮 GPU: $gpu_info"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🧠 RAM: $ram_info"
        echo ""
    else
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                System Information                      ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "🖥️  Operating System: $os_info"
        echo "🧠 Kernel Version: $kernel_info"
        echo "🖼️  Desktop Environment: $desktop_info"
        echo "⚡ CPU: $cpu_info"
        echo "🎮 GPU: $gpu_info"
        echo "🧠 RAM: $ram_info"
        echo ""
    fi

    # Installation mode and configuration summary
    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "📦 Installation Mode: $INSTALL_MODE"
        echo ""

        gum style --margin "1 2" --foreground "$GUM_PRIMARY_FG" --bold "╔══════════════════════════════════════════════════════════╗"
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "║              Installation Complete!                    ║"
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "╚══════════════════════════════════════════════════════════╝"
        echo ""
    else
        echo "📦 Installation Mode: $INSTALL_MODE"
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║              Installation Complete!                    ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
    fi

    # Show what was installed/configured
    if supports_gum; then
        gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ Security hardening (firewall, fail2ban, SSH)"
        gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ Performance optimization (CPU governor, ZRAM, filesystem)"
        gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ Shell environment (Zsh, Starship, Fastfetch)"
        gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ Development tools and package managers"

        if [ "${INSTALL_GAMING:-false}" = "true" ]; then
            gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ Gaming suite (Steam, Wine, GPU drivers)"
        fi

        case "${XDG_CURRENT_DESKTOP:-}" in
            *"KDE"*)
                gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ KDE Plasma configured (shortcuts, themes, settings)"
                ;;
            *"GNOME"*)
                gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ GNOME configured (extensions, themes, settings)"
                ;;
        esac

        echo ""
    else
        echo "✓ Security hardening (firewall, fail2ban, SSH)"
        echo "✓ Performance optimization (CPU governor, ZRAM, filesystem)"
        echo "✓ Shell environment (Zsh, Starship, Fastfetch)"
        echo "✓ Development tools and package managers"

        if [ "${INSTALL_GAMING:-false}" = "true" ]; then
            echo "✓ Gaming suite (Steam, Wine, GPU drivers)"
        fi

        case "${XDG_CURRENT_DESKTOP:-}" in
            *"KDE"*)
                echo "✓ KDE Plasma configured (shortcuts, themes, settings)"
                ;;
            *"GNOME"*)
                echo "✓ GNOME configured (extensions, themes, settings)"
                ;;
        esac

        echo ""
    fi

    # Maintenance and next steps
    if supports_gum; then
        gum style --margin "1 2" --foreground "$GUM_PRIMARY_FG" --bold "🔧 Maintenance & Next Steps:"
        echo ""
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "📋 Before system updates: Run 'system-update-snapshot'"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🔍 Check system health: 'systemctl status' commands"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "📁 View snapshots: 'snapper list' (Btrfs systems)"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "🎯 Gaming: Steam, Lutris, and Proton are ready"
        echo ""
    else
        echo "🔧 Maintenance & Next Steps:"
        echo ""
        echo "📋 Before system updates: Run 'system-update-snapshot'"
        echo "🔍 Check system health: 'systemctl status' commands"
        echo "📁 View snapshots: 'snapper list' (Btrfs systems)"
        echo "🎯 Gaming: Steam, Lutris, and Proton are ready"
        echo ""
    fi

    # Final reboot prompt with gum (no text fallback as requested)
    if supports_gum; then
        echo ""
        gum style --margin "1 2" --foreground "$GUM_WARNING_FG" --bold "🔄 System Reboot Required"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "All changes have been applied successfully."
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "A system reboot is recommended to ensure everything works properly."
        echo ""

        if gum confirm "Reboot your system now to apply all changes?" --default=true; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Reboot confirmed. Preparing system..."

            # Silently remove gum package before reboot
            if [ "${GUM_INSTALLED_BY_SCRIPT:-false}" = "true" ]; then
                log_info "Removing temporary gum package..."
                case "$DISTRO_ID" in
                    "arch") pacman -Rns --noconfirm gum >/dev/null 2>&1 || true ;;
                    "fedora") dnf remove -y gum >/dev/null 2>&1 || true ;;
                    "debian"|"ubuntu") apt remove -y --purge gum >/dev/null 2>&1 || true ;;
                esac
                log_info "Gum package removed successfully"
            fi

            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "🔄 Rebooting system in 3 seconds..."
            sleep 3
            reboot
        else
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" "→ Reboot deferred. Please reboot manually when ready."
            log_info "Reboot deferred by user choice"
        fi
    else
        # This should not happen as per user requirements, but fallback just in case
        echo "ERROR: Gum UI required for reboot functionality"
        echo "Please install gum and run the summary again"
        return 1
    fi

    return 0
}

export -f show_installation_summary
