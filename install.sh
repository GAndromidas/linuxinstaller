#!/bin/bash

# Script: install.sh
# Description: Script for setting up an Arch Linux system with various configurations and installations.
# Author: George Andromidas

# Default value for kernel headers
kernel_headers="linux-headers"  # Default to standard Linux headers

# Function to identify the installed Linux kernel type
identify_kernel_type() {
    # Purpose: Identifies the installed Linux kernel type and sets the appropriate kernel headers.
    # Dependencies: pacman
    # Output: Sets the variable kernel_headers based on the detected kernel type.
    printf "Identifying installed Linux kernel type... "
    echo
    if pacman -Q linux-zen &>/dev/null; then
        printf "Linux-Zen kernel found.\n"
        kernel_headers="linux-zen-headers"
    elif pacman -Q linux-hardened &>/dev/null; then
        printf "Linux-Hardened kernel found.\n"
        kernel_headers="linux-hardened-headers"
    elif pacman -Q linux-lts &>/dev/null; then
        printf "Linux-LTS kernel found.\n"
        kernel_headers="linux-lts-headers"
    else
        printf "Standard Linux kernel found.\n"
        kernel_headers="linux-headers"
    fi

    if [ $? -ne 0 ]; then
        printf "Error: Failed to identify the installed Linux kernel type.\n"
        exit 1
    fi
}

# Function to install kernel headers
install_kernel_headers() {
    # Purpose: Installs the kernel headers based on the identified kernel type.
    # Dependencies: sudo, pacman
    # Output: Installs the necessary kernel headers.
    identify_kernel_type  # Ensure kernel type is identified before installation
    echo
    printf "Installing kernel headers... "
    echo
    sudo pacman -S --needed --noconfirm "$kernel_headers"
    if [ $? -ne 0 ]; then
        printf "Error: Failed to install kernel headers.\n"
        exit 1
    else
        echo "Kernel headers installed successfully.\n"
    fi
}

# Function to remove Linux kernel fallback image
remove_kernel_fallback_image() {
    echo
    printf "Removing Linux kernel fallback image... "
    echo
    sudo rm /boot/loader/entries/*fallback*
    echo
    printf "Linux kernel fallback image removed successfully.\n"
}

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    # Purpose: Adds silent boot options to the Linux or Linux-Zen entry in Systemd-Boot.
    # Dependencies: find, sed
    # Output: Adds silent boot options to the Linux or Linux-Zen entry.
    echo
    printf "Making Systemd-Boot silent... "
    echo
    LOADER_DIR="/boot/loader"
    ENTRIES_DIR="$LOADER_DIR/entries"

    # Find the Linux or Linux-zen entry
    linux_entry=$(find "$ENTRIES_DIR" -type f \( -name '*_linux.conf' -o -name '*_linux-zen.conf' \) ! -name '*_linux-fallback.conf' -print -quit)

    if [ -z "$linux_entry" ]; then
        printf "\nError: Linux entry not found.\n"
        exit 1
    fi

    # Add silent boot options to the Linux entry
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"

    echo
    printf "Silent boot options added to Linux entry: %s.\n" "$(basename "$linux_entry")"
}

# Function to change loader.conf
change_loader_conf() {
    # Purpose: Changes loader.conf settings for boot configuration.
    # Output: Updates loader.conf settings.
    echo
    printf "Changing loader.conf... "
    echo
    LOADER_CONF="/boot/loader/loader.conf"
    sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    echo
    printf "Loader configuration updated.\n"
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    # Enables password feedback with asterisks in sudoers file.
    echo
    printf "Defaults env_reset,pwfeedback" | sudo EDITOR='tee -a' visudo
    echo
    printf "Password feedback enabled in sudoers.\n"
}

# Function to configure Pacman
configure_pacman() {
    # Purpose: Configures Pacman settings for package management.
    # Dependencies: sudo, sed
    # Output: Updates Pacman configuration settings.
    echo
    printf "Configuring Pacman... "
    echo
    sudo sed -i '
        /^#Color/s/^#//
        /^Color/a ILoveCandy
        /^#VerbosePkgLists/s/^#//
        s/^#ParallelDownloads = 5/ParallelDownloads = 10/
    ' /etc/pacman.conf
    if [ $? -ne 0 ]; then
        printf "Error: Failed to configure Pacman.\n"
        exit 1
    else
        printf "Pacman configuration updated successfully.\n"
    fi
}

# Function to update mirrorlist and modify reflector.conf
update_mirrorlist() {
    echo
    printf "Updating Mirrorlist... "
    echo
    # Install necessary packages
    sudo pacman -S --needed --noconfirm reflector rsync

    # Update reflector.conf
    sudo sed -i 's/^--latest .*/--latest 10/' /etc/xdg/reflector/reflector.conf
    sudo sed -i 's/^--sort .*/--sort rate/' /etc/xdg/reflector/reflector.conf
    echo
    printf "reflector.conf updated successfully.\n"

    # Run reflector to update mirrorlist
    sudo reflector --verbose --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
    echo
    printf "Mirrorlist updated successfully.\n"
}

# Function to update the system
update_system() {
    echo
    printf "Updating System... "
    echo
    sudo pacman -Syyu --noconfirm
    echo
    printf "System updated successfully.\n"
}

# Function to install Oh-My-ZSH and ZSH plugins
install_zsh() {
    echo
    printf "Configuring ZSH... "
    echo
    sudo pacman -S --needed --noconfirm zsh
    yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    sleep 1

    git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
    sleep 1

    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
    echo
    printf "ZSH configured successfully.\n"
}

# Function to change shell to ZSH
change_shell_to_zsh() {
    echo
    printf "Changing Shell to ZSH... "
    echo
    sudo chsh -s "$(which zsh)"
    chsh -s "$(which zsh)"
    echo
    printf "Shell changed to ZSH.\n"
}

# Function to move .zshrc
move_zshrc() {
    echo
    printf "Copying .zshrc to Home Folder... "
    echo
    mv "$HOME"/archinstaller/configs/.zshrc "$HOME"/
    echo
    printf ".zshrc copied successfully.\n"
}

# Function to install starship and move starship.toml
install_starship() {
    # Install Starship prompt automatically accepting with 'yes'
    curl -sS https://starship.rs/install.sh | sh -s -- -y

    # Check if the installation was successful
    if [ $? -eq 0 ]; then
    echo "Starship prompt installed successfully."

    # Create the .config directory if it doesn't exist
    mkdir -p "$HOME/.config"

    # Move the starship.toml file to the .config directory
    if [ -f "$HOME/archinstaller/configs/starship.toml" ]; then
    mv "$HOME/archinstaller/configs/starship.toml" "$HOME/.config/starship.toml"
    echo "starship.toml moved to $HOME/.config/"
    else
    echo "starship.toml not found in $HOME/archinstaller/configs/"
    fi
    else
    echo "Starship prompt installation failed."
    fi
}

# Function to configure locales
configure_locales() {
    echo
    printf "Configuring Locales... "
    echo
    sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
    echo
    printf "Locales generated successfully.\n"
}

# Function to install YAY
install_yay() {
    echo
    printf "Installing YAY... "
    echo
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
    echo
    printf "YAY installed successfully.\n"
}

# Function to install programs
install_programs() {
    echo
    printf "Installing Programs... "
    echo
    (cd "$HOME/archinstaller/scripts" && ./install_programs.sh)
    echo
    printf "Programs installed successfully.\n"

    # Call the next function here
    install_flatpak_programs
}

# Function to install flatpak programs
install_flatpak_programs() {
    echo
    printf "Installing Flatpak Programs... "
    echo
    (cd "$HOME/archinstaller/scripts" && ./install_flatpak_programs.sh)
    echo
    printf "Flatpak programs installed successfully.\n"

    # Call the next function here
    install_aur_programs
}

# Function to install AUR programs
install_aur_programs() {
    echo
    printf "Installing AUR Programs... "
    echo
    (cd "$HOME/archinstaller/scripts" && ./install_aur_programs.sh)
    echo
    printf "AUR programs installed successfully.\n"
}

# Function to enable services
enable_services() {
    echo
    printf "Enabling Services... \n"
    echo
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
            echo "$service enabled."
        else
            echo "$service is not installed."
        fi
    done

    echo
    printf "Services enabled successfully.\n"
}

# Function to create fastfetch config
create_fastfetch_config() {
    echo
    printf "Creating fastfetch config... "
    echo
    fastfetch --gen-config
    echo
    printf "fastfetch config created successfully.\n"

    echo
    printf "Copying fastfetch config from repository to ~/.config/fastfetch/... "
    echo
    cp "$HOME"/archinstaller/configs/config.jsonc "$HOME"/.config/fastfetch/config.jsonc
    echo
    printf "fastfetch config copied successfully.\n"
}

# Function to configure firewall
configure_firewall() {
    echo
    printf "Configuring Firewall... \n"
    echo

    if command -v ufw > /dev/null 2>&1; then
        echo "Using UFW for firewall configuration."
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw logging on
        sudo ufw limit ssh
        sudo ufw --force enable
    elif command -v firewall-cmd > /dev/null 2>&1; then
        echo "Using firewalld for firewall configuration."
        # Check if ssh service is already enabled
        if ! sudo firewall-cmd --permanent --list-services | grep -q "\<ssh\>"; then
            sudo firewall-cmd --permanent --add-service=ssh
            echo "SSH service added to firewalld."
        else
            echo "SSH service is already enabled in firewalld."
        fi

        # Add KDE Connect service if not already enabled
        if ! sudo firewall-cmd --permanent --list-services | grep -q "\<kdeconnect\>"; then
            sudo firewall-cmd --permanent --add-service=kdeconnect
            echo "KDE Connect service added to firewalld."
        else
            echo "KDE Connect service is already enabled in firewalld."
        fi

        # Reload firewall configuration
        sudo firewall-cmd --reload
    else
        echo "No compatible firewall found. Please install ufw or firewalld."
        return 1
    fi

    echo
    printf "Firewall configured successfully.\n"
}

# Function to clear unused packages and cache
clear_unused_packages_cache() {
    echo
    printf "Clearing Unused Packages and Cache... "
    echo
    sudo pacman -Rns $(pacman -Qdtq) --noconfirm
    sudo pacman -Sc --noconfirm
    yay -Sc --noconfirm
    rm -rf ~/.cache/* && sudo paccache -r
    echo
    printf "Unused packages and cache cleared successfully.\n"
}

# Function to delete the archinstaller folder
delete_archinstaller_folder() {
    echo
    printf "Deleting Archinstaller Folder... "
    echo
    sudo rm -rf "$HOME"/archinstaller
    echo
    printf "Archinstaller folder deleted successfully.\n"
}

# Function to reboot system
reboot_system() {
    echo
    printf "Rebooting System... "
    echo
    printf "Press 'y' to reboot now, or 'n' to cancel.\n"
    echo

    read -p "Do you want to reboot now? (y/n): " confirm_reboot

    # Validate user input for reboot confirmation
    while [[ ! "$confirm_reboot" =~ ^[yn]$ ]]; do
        read -p "Invalid input. Please enter 'y' to reboot now or 'n' to cancel: " confirm_reboot
    done

    if [[ "$confirm_reboot" == "y" ]]; then
    echo
        printf "Rebooting now... "
    echo
        sudo reboot
    else
    echo
        printf "Reboot canceled. You can reboot manually later by typing 'sudo reboot'.\n"
    echo
    fi
}

# Function to detect bootloader
detect_bootloader() {
    if [ -d "/sys/firmware/efi" ] && [ -d "/boot/loader" ]; then
        echo "systemd-boot detected."
        return 0
    else
        echo "GRUB detected or no bootloader detected."
        return 1
    fi
}

# Function to install GRUB theme
install_grub_theme() {
    echo
    printf "Installing GRUB theme... "
    echo
    cd /tmp
    git clone https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes
    cd Top-5-Bootloader-Themes
    sudo ./install.sh
    cd ..
    rm -rf Top-5-Bootloader-Themes
    echo
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
