#!/bin/bash
# set -uo pipefail # Inherited from install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
if [ -z "${DISTRO_ID:-}" ]; then
    [ -f "$SCRIPT_DIR/distro_check.sh" ] && source "$SCRIPT_DIR/distro_check.sh" && detect_distro && setup_package_providers
fi

setup_universal_packages() {
    step "Setting up Universal Package Managers"

    if [ "$DISTRO_ID" == "arch" ]; then
        # --- Arch Linux Specific Setup (Yay + Rate Mirrors) ---

        if command -v yay &>/dev/null; then
            log_success "yay is already installed"
        else
            log_info "Installing yay (AUR Helper)..."

            # Ensure prerequisites
            if ! sudo pacman -S --noconfirm --needed base-devel git >> "$INSTALL_LOG" 2>&1; then
                log_error "Failed to install base-devel or git."
                return 1
            fi

            # Build in temp dir
            local temp_dir=$(mktemp -d)
            chmod 777 "$temp_dir"

            local run_as_user=""
            if [ "$EUID" -eq 0 ]; then
                 if [ -n "${SUDO_USER:-}" ]; then
                     run_as_user="sudo -u $SUDO_USER"
                     chown "$SUDO_USER:$SUDO_USER" "$temp_dir"
                 else
                     # Fallback for root without SUDO_USER (rare)
                     run_as_user="sudo -u nobody"
                     chown nobody:nobody "$temp_dir"
                 fi
            fi

            cd "$temp_dir" || return 1

            log_to_file "Cloning yay..."
            if $run_as_user git clone https://aur.archlinux.org/yay.git . >> "$INSTALL_LOG" 2>&1; then
                echo -e "${YELLOW}Building yay...${RESET}"
                # makepkg -si handles sudo internally for the install part
                if $run_as_user makepkg -si --noconfirm --needed >> "$INSTALL_LOG" 2>&1; then
                    log_success "Yay installed successfully"
                else
                    log_error "Failed to build yay (check log for details)"
                fi
            else
                log_error "Failed to clone yay repository (check log for details)"
            fi

            cd - >/dev/null
            rm -rf "$temp_dir"
        fi

        # Install rate-mirrors-bin
        if ! command -v rate-mirrors &>/dev/null; then
            ui_info "Installing rate-mirrors-bin..."
            if command -v yay &>/dev/null; then
                 if yay -S --noconfirm rate-mirrors-bin >> "$INSTALL_LOG" 2>&1; then
                     log_success "rate-mirrors installed"
                 else
                     log_warning "Failed to install rate-mirrors-bin"
                 fi
            else
                 log_warning "Yay missing, skipping rate-mirrors."
            fi
        fi

        # Update mirrorlist
        if command -v rate-mirrors &>/dev/null; then
             ui_info "Optimizing mirrorlist..."
             if sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch >> "$INSTALL_LOG" 2>&1; then
                 log_success "Mirrorlist optimized"
             else
                 log_warning "Failed to update mirrorlist"
             fi
        fi
    fi

    # --- Universal Setup (Flatpak/Snap) ---

    # Setup Flatpak if needed
        if [ "$PRIMARY_UNIVERSAL_PKG" == "flatpak" ] || [ "$BACKUP_UNIVERSAL_PKG" == "flatpak" ]; then
            if ! command -v flatpak >/dev/null; then
                ui_info "Installing Flatpak..."
                $PKG_INSTALL flatpak >> "$INSTALL_LOG" 2>&1
            fi

            # Add Flathub
            flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >> "$INSTALL_LOG" 2>&1
            ui_success "Flatpak configured."
        fi

        # Setup Snap if needed (Ubuntu usually has it)
        if [ "$PRIMARY_UNIVERSAL_PKG" == "snap" ] || [ "$BACKUP_UNIVERSAL_PKG" == "snap" ]; then
            if ! command -v snap >/dev/null; then
                ui_info "Installing Snap..."
                if [ "$DISTRO_ID" == "fedora" ]; then
                     sudo dnf install -y snapd >> "$INSTALL_LOG" 2>&1
                     sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null
                elif [ "$DISTRO_ID" == "arch" ]; then
                     if command -v yay >/dev/null; then
                         yay -S --noconfirm snapd >> "$INSTALL_LOG" 2>&1
                         sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null || true
                     fi
                else
                     $PKG_INSTALL snapd >> "$INSTALL_LOG" 2>&1
                fi
                sudo systemctl enable --now snapd.socket >> "$INSTALL_LOG" 2>&1
            else
                ui_success "Snap is already installed."
            fi
        fi
}

setup_universal_packages
