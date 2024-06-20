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

# Function to identify the installed Linux kernel type
identify_kernel_type() {
    printf "Identifying installed Linux kernel type...\n"
    if pacman -Q linux-zen &>/dev/null; then
        KERNEL_HEADERS="linux-zen-headers"
    elif pacman -Q linux-hardened &>/dev/null; then
        KERNEL_HEADERS="linux-hardened-headers"
    elif pacman -Q linux-lts &>/dev/null; then
        KERNEL_HEADERS="linux-lts-headers"
    fi
    printf "%s kernel headers will be installed.\n" "$KERNEL_HEADERS"
}

# Function to install kernel headers
install_kernel_headers() {
    identify_kernel_type
    printf "Installing kernel headers...\n"
    if sudo pacman -S --needed --noconfirm "$KERNEL_HEADERS"; then
        printf "Kernel headers installed successfully.\n"
    else
        printf "Error: Failed to install kernel headers.\n"
        exit 1
    fi
}

# Function to remove Linux kernel fallback image
remove_kernel_fallback_image() {
    printf "Removing Linux kernel fallback image...\n"
    sudo rm /boot/loader/entries/*fallback* && printf "Linux kernel fallback image removed successfully.\n"
}

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    printf "Making Systemd-Boot silent...\n"
    linux_entry=$(find "$ENTRIES_DIR" -type f \( -name '*_linux.conf' -o -name '*_linux-zen.conf' \) ! -name '*_linux-fallback.conf' -print -quit)

    if [ -z "$linux_entry" ]; then
        printf "Error: Linux entry not found.\n"
        exit 1
    fi

    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry" && \
    printf "Silent boot options added to Linux entry: %s.\n" "$(basename "$linux_entry")"
}

# Function to change loader.conf
change_loader_conf() {
    printf "Changing loader.conf...\n"
    sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    printf "Loader configuration updated.\n"
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    printf "Enabling asterisks for password input in sudoers...\n"
    echo "Defaults env_reset,pwfeedback" | sudo EDITOR='tee -a' visudo && \
    printf "Password feedback enabled in sudoers.\n"
}

# Function to configure Pacman
configure_pacman() {
    printf "Configuring Pacman...\n"
    sudo sed -i '
        /^#Color/s/^#//
        /^Color/a ILoveCandy
        /^#VerbosePkgLists/s/^#//
        s/^#ParallelDownloads = 5/ParallelDownloads = 10/
    ' /etc/pacman.conf && \
    printf "Pacman configuration updated successfully.\n"
}

# Function to update mirrorlist and modify reflector.conf
update_mirrorlist() {
    printf "Updating Mirrorlist...\n"
    sudo pacman -S --needed --noconfirm reflector rsync

    sudo sed -i 's/^--latest .*/--latest 10/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^--sort .*/--sort rate/' /etc/xdg/reflector/reflector.conf
    printf "reflector.conf updated successfully.\n"

    sudo reflector --verbose --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist && \
    sudo pacman -Syyy && \
    printf "Mirrorlist updated successfully.\n"
}

# Function to update the system
update_system() {
    printf "Updating System...\n"
    sudo pacman -Syyu --noconfirm && \
    printf "System updated successfully.\n"
}

# Function to install Oh-My-ZSH and ZSH plugins
install_zsh() {
    printf "Configuring ZSH...\n"
    sudo pacman -S --needed --noconfirm zsh
    yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    sleep 1

    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    sleep 1

    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    printf "ZSH configured successfully.\n"
}

# Function to change shell to ZSH
change_shell_to_zsh() {
    printf "Changing Shell to ZSH...\n"
    sudo chsh -s "$(which zsh)"
    chsh -s "$(which zsh)"
    printf "Shell changed to ZSH.\n"
}

# Function to move .zshrc
move_zshrc() {
    printf "Copying .zshrc to Home Folder...\n"
    mv "$CONFIGS_DIR/.zshrc" "$HOME/" && \
    printf ".zshrc copied successfully.\n"
}

# Function to install starship and move starship.toml
install_starship() {
    printf "Installing Starship prompt...\n"
    if curl -sS https://starship.rs/install.sh | sh -s -- -y; then
        printf "Starship prompt installed successfully.\n"
        mkdir -p "$HOME/.config"
        if [ -f "$CONFIGS_DIR/starship.toml" ]; then
            mv "$CONFIGS_DIR/starship.toml" "$HOME/.config/starship.toml"
            printf "starship.toml moved to $HOME/.config/\n"
        else
            printf "starship.toml not found in $CONFIGS_DIR/\n"
        fi
    else
        printf "Starship prompt installation failed.\n"
    fi
}

# Function to configure locales
configure_locales() {
    printf "Configuring Locales...\n"
    sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen && \
    printf "Locales generated successfully.\n"
}

# Function to install YAY
install_yay() {
    printf "Installing YAY...\n"
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
    printf "YAY installed successfully.\n"
}

# Function to install programs
install_programs() {
    printf "Installing Programs...\n"
    (cd "$SCRIPTS_DIR" && ./install_programs.sh) && \
    printf "Programs installed successfully.\n"

    install_flatpak_programs
}

# Function to install flatpak programs
install_flatpak_programs() {
    printf "Installing Flatpak Programs...\n"
    (cd "$SCRIPTS_DIR" && ./install_flatpak_programs.sh) && \
    printf "Flatpak programs installed successfully.\n"

    install_aur_programs
}

# Function to install AUR programs
install_aur_programs() {
    printf "Installing AUR Programs...\n"
    (cd "$SCRIPTS_DIR" && ./install_aur_programs.sh) && \
    printf "AUR programs installed successfully.\n"
}

# Function to enable services
enable_services() {
    printf "Enabling Services...\n"
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
        "ufw"
    )

    for service in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^$service"; then
            sudo systemctl enable --now "$service"
            printf "%s enabled.\n" "$service"
        else
            printf "%s is not installed.\n" "$service"
        fi
    done

    printf "Services enabled successfully.\n"
}

# Function to create fastfetch config
create_fastfetch_config() {
    printf "Creating fastfetch config...\n"
    fastfetch --gen-config && \
    printf "fastfetch config created successfully.\n"

    printf "Copying fastfetch config from repository to ~/.config/fastfetch/...\n"
    cp "$CONFIGS_DIR/config.jsonc" "$HOME/.config/fastfetch/config.jsonc" && \
    printf "fastfetch config copied successfully.\n"
}

# Function to configure firewall
configure_firewall() {
    printf "Configuring Firewall...\n"

    if command -v ufw > /dev/null 2>&1; then
        printf "Using UFW for firewall configuration.\n"
        commands=(
            "sudo ufw default deny incoming"
            "sudo ufw default allow outgoing"
            "sudo ufw allow ssh"
            "sudo ufw logging on"
            "sudo ufw limit ssh"
            "sudo ufw --force enable"
        )
    elif command -v firewall-cmd > /dev/null 2>&1; then
        printf "Using firewalld for firewall configuration.\n"
        commands=(
            "sudo firewall-cmd --permanent --add-service=ssh"
            "sudo firewall-cmd --permanent --add-service=kdeconnect"
            "sudo firewall-cmd --permanent --add-service=mdns"
            "sudo firewall-cmd --reload"
        )
    else
        printf "No compatible firewall found. Please install ufw or firewalld.\n"
        return 1
    fi

    for cmd in "${commands[@]}"; do
        eval "$cmd"
    done

    printf "Firewall configured successfully.\n"
}

# Function to clear unused packages and cache
clear_unused_packages_cache() {
    printf "Clearing Unused Packages and Cache...\n"
    sudo pacman -Rns $(pacman -Qdtq) --noconfirm
    sudo pacman -Sc --noconfirm
    yay -Sc --noconfirm
    rm -rf ~/.cache/* && sudo paccache -r
    printf "Unused packages and cache cleared successfully.\n"
}

# Function to delete the archinstaller folder
delete_archinstaller_folder() {
    printf "Deleting Archinstaller Folder...\n"
    sudo rm -rf "$HOME/archinstaller" && \
    printf "Archinstaller folder deleted successfully.\n"
}

# Function to reboot system
reboot_system() {
    printf "Rebooting System...\n"
    printf "Press 'y' to reboot now, or 'n' to cancel.\n"

    read -p "Do you want to reboot now? (y/n): " confirm_reboot

    while [[ ! "$confirm_reboot" =~ ^[yn]$ ]]; do
        read -p "Invalid input. Please enter 'y' to reboot now or 'n' to cancel: " confirm_reboot
    done

    if [[ "$confirm_reboot" == "y" ]]; then
        printf "Rebooting now...\n"
        sudo reboot
    else
        printf "Reboot canceled. You can reboot manually later by typing 'sudo reboot'.\n"
    fi
}

# Function to detect bootloader
detect_bootloader() {
    if [ -d "/sys/firmware/efi" ] && [ -d "/boot/loader" ]; then
        printf "systemd-boot detected.\n"
        return 0
    else
        printf "GRUB detected or no bootloader detected.\n"
        return 1
    fi
}

# Function to install GRUB theme
install_grub_theme() {
    printf "Installing GRUB theme...\n"
    cd /tmp
    git clone https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes
    cd Top-5-Bootloader-Themes
    sudo ./install.sh
    cd ..
    rm -rf Top-5-Bootloader-Themes
    printf "GRUB theme installed successfully.\n"
}

# Main script

# Run functions
identify_kernel_type
install_kernel_headers

if detect_bootloader; then
    remove_kernel_fallback_image
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
