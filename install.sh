#!/bin/bash

# Script: install.sh
# Description: Script for setting up an Arch Linux system with various configurations and installations.
# Author: George Andromidas

# Variables
KERNEL_HEADERS="linux-headers"  # Default to standard Linux headers
LOADER_DIR="/boot/loader"
ENTRIES_DIR="$LOADER_DIR/entries"
LOADER_CONF="/boot/loader/loader.conf"
CONFIGS_DIR="$HOME/archinstaller/configs"
SCRIPTS_DIR="$HOME/archinstaller/scripts"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print messages with colors
print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

# Function to identify the installed Linux kernel type and install kernel headers
install_kernel_headers() {
    print_info "Identifying installed Linux kernel type..."

    if pacman -Q linux-zen &>/dev/null; then
        KERNEL_HEADERS="linux-zen-headers"
    elif pacman -Q linux-hardened &>/dev/null; then
        KERNEL_HEADERS="linux-hardened-headers"
    elif pacman -Q linux-lts &>/dev/null; then
        KERNEL_HEADERS="linux-lts-headers"
    fi

    print_info "Installing $KERNEL_HEADERS..."
    if sudo pacman -S --needed --noconfirm "$KERNEL_HEADERS"; then
        print_success "Kernel headers ($KERNEL_HEADERS) installed successfully."
    else
        print_error "Error: Failed to install kernel headers ($KERNEL_HEADERS)."
        exit 1
    fi
}

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    print_info "Making Systemd-Boot silent..."
    linux_entry=$(find "$ENTRIES_DIR" -type f \( -name '*_linux.conf' -o -name '*_linux-zen.conf' \) ! -name '*_linux-fallback.conf' -print -quit)

    if [ -z "$linux_entry" ]; then
        print_error "Error: Linux entry not found."
        exit 1
    fi

    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry" && \
    print_success "Silent boot options added to Linux entry: $(basename "$linux_entry")."
}

# Function to change loader.conf
change_loader_conf() {
    print_info "Changing loader.conf..."
    sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    print_success "Loader configuration updated."
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    print_info "Enabling asterisks for password input in sudoers..."
    echo "Defaults env_reset,pwfeedback" | sudo EDITOR='tee -a' visudo && \
    print_success "Password feedback enabled in sudoers."
}

# Function to configure Pacman
configure_pacman() {
    print_info "Configuring Pacman..."
    sudo sed -i '
        /^#Color/s/^#//
        /^Color/a ILoveCandy
        /^#VerbosePkgLists/s/^#//
        s/^#ParallelDownloads = 5/ParallelDownloads = 10/
    ' /etc/pacman.conf && \
    print_success "Pacman configuration updated successfully."
}

# Function to update mirrorlist and modify reflector.conf
update_mirrorlist() {
    print_info "Updating Mirrorlist..."
    sudo pacman -S --needed --noconfirm reflector rsync

    sudo sed -i 's/^--latest .*/--latest 10/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^--sort .*/--sort rate/' /etc/xdg/reflector/reflector.conf
    print_success "reflector.conf updated successfully."

    sudo reflector --verbose --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist && \
    sudo pacman -Syyy && \
    print_success "Mirrorlist updated successfully."
}

# Function to update the system
update_system() {
    print_info "Updating System..."
    sudo pacman -Syyu --noconfirm && \
    print_success "System updated successfully."
}

# Function to install Oh-My-ZSH and ZSH plugins
install_zsh() {
    print_info "Configuring ZSH..."
    sudo pacman -S --needed --noconfirm zsh
    yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    sleep 1

    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    sleep 1

    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    print_success "ZSH configured successfully."
}

# Function to change shell to ZSH
change_shell_to_zsh() {
    print_info "Changing Shell to ZSH..."
    sudo chsh -s "$(which zsh)"
    chsh -s "$(which zsh)"
    print_success "Shell changed to ZSH."
}

# Function to move .zshrc
move_zshrc() {
    print_info "Copying .zshrc to Home Folder..."
    mv "$CONFIGS_DIR/.zshrc" "$HOME/" && \
    print_success ".zshrc copied successfully."
}

# Function to install starship and move starship.toml
install_starship() {
    print_info "Installing Starship prompt..."
    if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
        print_success "Starship prompt installed successfully."
        mkdir -p "$HOME/.config"
        if [ -f "$CONFIGS_DIR/starship.toml" ]; then
            mv "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
            print_success "starship.toml moved to $HOME/.config/"
        else
            print_warning "starship.toml not found in $CONFIGS_DIR/"
        fi
    else
        print_error "Starship prompt installation failed."
    fi
}

# Function to configure locales
configure_locales() {
    print_info "Configuring Locales..."
    sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen && \
    print_success "Locales generated successfully."
}

# Function to install YAY
install_yay() {
    print_info "Installing YAY..."
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
    print_success "YAY installed successfully."
}

# Function to install programs
install_programs() {
    print_info "Installing Programs..."
    (cd "$SCRIPTS_DIR" && ./install_programs.sh) && \
    print_success "Programs installed successfully."

    install_flatpak_programs
}

# Function to install flatpak programs
install_flatpak_programs() {
    print_info "Installing Flatpak Programs..."
    (cd "$SCRIPTS_DIR" && ./install_flatpak_programs.sh) && \
    print_success "Flatpak programs installed successfully."

    install_aur_programs
}

# Function to install AUR programs
install_aur_programs() {
    print_info "Installing AUR Programs..."
    (cd "$SCRIPTS_DIR" && ./install_aur_programs.sh) && \
    print_success "AUR programs installed successfully."
}

# Function to enable services
enable_services() {
    print_info "Enabling Services..."
    local services=(
        "bluetooth"
        "cronie"
        "firewalld"
        "fstrim.timer"
        "paccache.timer"
        "reflector.service"
        "reflector.timer"
        "sshd"
        "teamviewerd.service"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            sudo systemctl enable --now "$service"
            print_success "$service enabled."
        else
            print_warning "$service is not installed."
        fi
    done

    print_success "Services enabled successfully."
}

# Function to create fastfetch config
create_fastfetch_config() {
    print_info "Creating fastfetch config..."
    fastfetch --gen-config && \
    print_success "fastfetch config created successfully."

    print_info "Copying fastfetch config from repository to ~/.config/fastfetch/..."
    cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc" && \
    print_success "fastfetch config copied successfully."
}

# Function to configure firewall
configure_firewall() {
    print_info "Configuring Firewall..."

    if command -v firewall-cmd > /dev/null 2>&1; then
        print_info "Using firewalld for firewall configuration."

        commands=()

        # Check if SSH is already allowed
        if ! sudo firewall-cmd --permanent --list-services | grep -q "\bssh\b"; then
            commands+=("sudo firewall-cmd --permanent --add-service=ssh")
        else
            print_warning "SSH is already allowed. Skipping SSH service configuration."
        fi

        # Check if KDE Connect is installed
        if pacman -Q kdeconnect &>/dev/null; then
            commands+=("sudo firewall-cmd --permanent --add-service=kdeconnect")
        else
            print_warning "KDE Connect is not installed. Skipping kdeconnect service configuration."
        fi

        # Reload firewall configuration
        commands+=("sudo firewall-cmd --reload")

        # Execute commands
        for cmd in "${commands[@]}"; do
            eval "$cmd"
        done

        print_success "Firewall configured successfully."

    else
        print_error "Firewalld not found. Please install firewalld."
        return 1
    fi
}

# Function to clear unused packages and cache
clear_unused_packages_cache() {
    print_info "Clearing Unused Packages and Cache..."
    sudo pacman -Rns $(pacman -Qdtq) --noconfirm
    sudo pacman -Sc --noconfirm
    yay -Sc --noconfirm
    rm -rf ~/.cache/* && sudo paccache -r
    print_success "Unused packages and cache cleared successfully."
}

# Function to delete the archinstaller folder
delete_archinstaller_folder() {
    print_info "Deleting Archinstaller Folder..."
    sudo rm -rf "$HOME/archinstaller" && \
    print_success "Archinstaller folder deleted successfully."
}

# Function to reboot system
reboot_system() {
    print_info "Rebooting System..."
    printf "${YELLOW}Do you want to reboot now? (Y/n)${RESET} "

    read -rp "" confirm_reboot

    # Convert input to lowercase for case-insensitive comparison
    confirm_reboot="${confirm_reboot,,}"

    # Handle empty input (Enter pressed)
    if [[ -z "$confirm_reboot" ]]; then
        confirm_reboot="y"  # Apply "yes" if Enter is pressed
    fi

    # Validate input
    while [[ ! "$confirm_reboot" =~ ^(y|n)$ ]]; do
        read -rp "Invalid input. Please enter 'Y' to reboot now or 'n' to cancel: " confirm_reboot
        confirm_reboot="${confirm_reboot,,}"
    done

    if [[ "$confirm_reboot" == "y" ]]; then
        print_info "Rebooting now..."
        sudo reboot
    else
        print_warning "Reboot canceled. You can reboot manually later by typing 'sudo reboot'."
    fi
}

# Function to detect bootloader
detect_bootloader() {
    if [ -d "/sys/firmware/efi" ] && [ -d "/boot/loader" ]; then
        print_info "systemd-boot detected."
        return 0
    else
        print_info "GRUB detected or no bootloader detected."
        return 1
    fi
}

# Function to install GRUB theme
install_grub_theme() {
    print_info "Installing GRUB theme..."
    cd /tmp
    git clone https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes
    cd Top-5-Bootloader-Themes
    sudo ./install.sh
    cd ..
    rm -rf Top-5-Bootloader-Themes
    print_success "GRUB theme installed successfully."
}

# Main script

# Run functions
install_kernel_headers

if detect_bootloader; then
    make_systemd_boot_silent
    change_loader_conf
else
    install_grub_theme
fi

enable_asterisks_sudo
configure_pacman
update_mirrorlist
update_system
install_zsh
change_shell_to_zsh
move_zshrc
install_starship
configure_locales
install_yay
install_programs
enable_services
create_fastfetch_config
configure_firewall
clear_unused_packages_cache
delete_archinstaller_folder
reboot_system
