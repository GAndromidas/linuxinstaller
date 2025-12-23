#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
# distro_check logic
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro && setup_package_providers
fi

step "Setting up Universal Package Managers"

if [ "$DISTRO_ID" == "arch" ]; then
    # --- Arch Linux Specific Setup (Yay + Rate Mirrors) ---
    
    # Check if yay is already installed
    if command -v yay &>/dev/null; then
        log_success "yay is already installed"
    else
        log_info "Installing yay (AUR Helper)..."
        
        # Ensure prerequisites
        if ! sudo pacman -S --noconfirm --needed base-devel git >/dev/null 2>&1; then
            log_error "Failed to install base-devel or git."
            exit 1
        fi

        # Build in temp dir
        local temp_dir=$(mktemp -d)
        chmod 777 "$temp_dir"
        
        # Determine user to run as (makepkg cannot run as root)
        local run_as_user=""
        if [ "$EUID" -eq 0 ]; then
             if [ -n "${SUDO_USER:-}" ]; then
                 run_as_user="sudo -u $SUDO_USER"
                 chown "$SUDO_USER:$SUDO_USER" "$temp_dir"
             else
                 run_as_user="sudo -u nobody"
                 chown nobody:nobody "$temp_dir"
             fi
        fi

        cd "$temp_dir" || exit 1
        
        if $run_as_user git clone https://aur.archlinux.org/yay.git . >/dev/null 2>&1; then
            echo -e "${YELLOW}Building yay...${RESET}"
            # makepkg -si handles sudo internally for the install part
            if $run_as_user makepkg -si --noconfirm --needed >/dev/null 2>&1; then
                log_success "Yay installed successfully"
            else
                log_error "Failed to build yay"
            fi
        else
            log_error "Failed to clone yay repository"
        fi
        
        cd - >/dev/null
        rm -rf "$temp_dir"
    fi

    # Install rate-mirrors-bin
    if ! command -v rate-mirrors &>/dev/null; then
        ui_info "Installing rate-mirrors-bin for faster downloads..."
        if yay -S --noconfirm rate-mirrors-bin; then
             log_success "rate-mirrors installed"
        else
             log_warning "Failed to install rate-mirrors-bin"
        fi
    fi

    # Update mirrorlist
    if command -v rate-mirrors &>/dev/null; then
         ui_info "Optimizing mirrorlist..."
         if sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch; then
             log_success "Mirrorlist optimized"
         else
             log_warning "Failed to update mirrorlist"
         fi
    fi

else
    # --- Non-Arch Distros (Flatpak/Snap Setup) ---
    
    # Setup Flatpak if needed
    if [ "$PRIMARY_UNIVERSAL_PKG" == "flatpak" ] || [ "$BACKUP_UNIVERSAL_PKG" == "flatpak" ]; then
        if ! command -v flatpak >/dev/null; then
            ui_info "Installing Flatpak..."
            $PKG_INSTALL flatpak
        fi
        
        # Add Flathub
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        ui_success "Flatpak configured."
    fi

    # Setup Snap if needed (Ubuntu usually has it)
    if [ "$PRIMARY_UNIVERSAL_PKG" == "snap" ] || [ "$BACKUP_UNIVERSAL_PKG" == "snap" ]; then
        if ! command -v snap >/dev/null; then
            ui_info "Installing Snap..."
            if [ "$DISTRO_ID" == "fedora" ]; then
                 sudo dnf install -y snapd
                 sudo ln -s /var/lib/snapd/snap /snap
            else
                 $PKG_INSTALL snapd
            fi
            sudo systemctl enable --now snapd.socket
        else
            ui_success "Snap is already installed."
        fi
    fi
fi
