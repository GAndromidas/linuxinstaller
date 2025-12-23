#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro
fi

# Helper to deduplicate kernel parameters
merge_params() {
  echo "$1 $2" | awk '{
    for (i=1; i<=NF; i++) {
      if (!seen[$i]++) {
        printf "%s%s", (count++ ? " " : ""), $i
      }
    }
    printf "\n"
  }'
}

# --- Generic GRUB Configuration ---
configure_grub() {
    step "Configuring GRUB"

    if [ ! -f /etc/default/grub ]; then
        log_info "GRUB config not found. Skipping."
        return
    fi

    # Common optimizations
    # Set timeout to 3s if not set
    if grep -q "GRUB_TIMEOUT=" /etc/default/grub; then
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
    else
        echo "GRUB_TIMEOUT=3" | sudo tee -a /etc/default/grub
    fi

    # Params to add
    local params="quiet splash"
    
    # Read current
    local current_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub || echo "")
    if [ -z "$current_line" ]; then
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$params\"" | sudo tee -a /etc/default/grub
    else
        local current_val=$(echo "$current_line" | cut -d'=' -f2- | sed "s/^['\"]//;s/['\"]$//")
        local new_val=$(merge_params "$current_val" "$params")
        sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$new_val\"|" /etc/default/grub
    fi

    log_info "Regenerating GRUB config..."
    
    case "$DISTRO_ID" in
        arch)
            sudo grub-mkconfig -o /boot/grub/grub.cfg
            ;;
        debian|ubuntu)
            sudo update-grub
            ;;
        fedora)
            if [ -d /sys/firmware/efi ]; then
                sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg
            else
                sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            fi
            ;;
    esac
}

# --- Arch Specifics (Secure Boot / systemd-boot) ---
configure_arch_boot() {
    if [ "$DISTRO_ID" != "arch" ]; then return; fi
    
    # Check for systemd-boot
    if [ -d "/boot/loader/entries" ]; then
        step "Configuring systemd-boot (Arch)"
        # (Simplified from original: just ensure loader.conf exists)
        if [ ! -f /boot/loader/loader.conf ]; then
             echo "default @saved" | sudo tee /boot/loader/loader.conf
             echo "timeout 3" | sudo tee -a /boot/loader/loader.conf
        fi
    fi
    
    # Secure Boot (sbctl)
    if [ "${SECURE_BOOT_SETUP:-false}" = "true" ]; then
         step "Configuring Secure Boot (sbctl)"
         if ! command -v sbctl >/dev/null; then
             sudo pacman -S --noconfirm sbctl
         fi
         # Just verify status, don't auto-sign blindly in universal script unless requested
         sudo sbctl status
    fi
}

# --- Main ---
main() {
    # Detect bootloader type roughly
    if [ -d /sys/firmware/efi ]; then
        log_info "UEFI System detected."
    fi

    # Configure GRUB if present
    if command -v grub-mkconfig >/dev/null || command -v update-grub >/dev/null || command -v grub2-mkconfig >/dev/null; then
        configure_grub
    fi

    # Run Arch specifics
    configure_arch_boot
}

main "$@"
