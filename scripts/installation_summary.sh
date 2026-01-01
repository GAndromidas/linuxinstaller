#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"

# Show installation summary with beautiful formatting
show_installation_summary() {
    step "Installation Summary"

    # Show distro info
    if supports_gum; then
        gum style --margin "1 0" --foreground "$GUM_PRIMARY_FG" --bold "System Information"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "  OS: ${PRETTY_NAME:-Unknown}"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "  Desktop: ${XDG_CURRENT_DESKTOP:-None}"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "  CPU: ${DETECTED_CPU:-Unknown}"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "  GPU: ${DETECTED_GPU:-Unknown}"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "  RAM: ${DETECTED_RAM:-Unknown}"
        echo ""
    else
        echo "======================================"
        echo "        System Information"
        echo "======================================"
        echo "OS: ${PRETTY_NAME:-Unknown}"
        echo "Desktop: ${XDG_CURRENT_DESKTOP:-None}"
        echo "CPU: ${DETECTED_CPU:-Unknown}"
        echo "GPU: ${DETECTED_GPU:-Unknown}"
        echo "RAM: ${DETECTED_RAM:-Unknown}"
        echo "======================================"
        echo ""
    fi

    # Show installation mode
    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Installation Mode: $INSTALL_MODE"
        echo ""
    else
        echo "Installation Mode: $INSTALL_MODE"
        echo ""
    fi

    # Show configuration summary
    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" "Installation completed"
        echo ""
    else
        echo "Installation completed"
        echo ""
    fi

    # Show gaming status
    if [ "${INSTALL_GAMING:-false}" = "true" ]; then
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_SUCCESS_FG" "✓ Gaming Packages: Enabled"
        else
            echo "Gaming Packages: Enabled"
        fi
    else
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_WARNING_FG" "✗ Gaming Packages: Disabled"
        else
            echo "Gaming Packages: Disabled"
        fi
    fi

    # Next steps
    if supports_gum; then
        gum style --margin "1 0" --foreground "$GUM_PRIMARY_FG" --bold "Next Steps:"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "• Reboot to apply all changes"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "• After reboot, your system will be fully configured"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "• Run 'system-update-snapshot' before system updates"
        echo ""
    else
        echo "Next Steps:"
        echo "  • Reboot to apply all changes"
        echo "  • After reboot, your system will be fully configured"
        echo "  • Run 'system-update-snapshot' before system updates"
        echo ""
    fi

    # Offer reboot (only once!)
    if supports_gum; then
        if gum confirm "Reboot your system now to apply all changes?" --default=false; then
            log_info "Rebooting system in 10 seconds..."
            sleep 10
            reboot
        else
            log_info "Reboot deferred. Please reboot manually when ready."
        fi
    else
        echo ""
        read -r -p "Reboot your system now to apply all changes? [Y/n]: " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            log_info "Rebooting system in 10 seconds..."
            sleep 10
            reboot
        else
            log_info "Reboot deferred. Please reboot manually when ready."
        fi
    fi

    return 0
}

export -f show_installation_summary
