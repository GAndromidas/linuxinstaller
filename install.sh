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
    printf "Installing kernel headers... "
    sudo pacman -S --needed --noconfirm "$kernel_headers"
    if [ $? -ne 0 ]; then
        printf "Error: Failed to install kernel headers.\n"
        exit 1
    else
        printf "Kernel headers installed successfully.\n"
    fi
}

# Function to remove Linux kernel fallback image
remove_kernel_fallback_image() {
    printf "Removing Linux kernel fallback image... "
    sudo rm /boot/loader/entries/*fallback*
    printf "Linux kernel fallback image removed successfully.\n"
}

# Function to configure Pacman
configure_pacman() {
    # Purpose: Configures Pacman settings for package management.
    # Dependencies: sudo, sed
    # Output: Updates Pacman configuration settings.
    printf "Configuring Pacman... "
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

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    # Purpose: Adds silent boot options to the Linux or Linux-Zen entry in Systemd-Boot.
    # Dependencies: find, sed
    # Output: Adds silent boot options to the Linux or Linux-Zen entry.
    printf "Making Systemd-Boot silent... "
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
    
    printf "Silent boot options added to Linux entry: %s.\n" "$(basename "$linux_entry")"
}

# Function to change loader.conf
change_loader_conf() {
    # Purpose: Changes loader.conf settings for boot configuration.
    # Output: Updates loader.conf settings.
    printf "Changing loader.conf... "
    LOADER_CONF="/boot/loader/loader.conf"
    sudo sed -i 's/^timeout.*/timeout 3/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    printf "Loader configuration updated.\n"
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    # Enables password feedback with asterisks in sudoers file.
    echo "Defaults env_reset,pwfeedback" | sudo EDITOR='tee -a' visudo
    printf "Password feedback enabled in sudoers.\n"
}

# Function to update mirrorlist
update_mirrorlist() {
    printf "Updating Mirrorlist... "
    sudo pacman -S --needed --noconfirm reflector rsync
    sudo reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
    printf "Mirrorlist updated successfully.\n"
}

# Function to update the system
update_system() {
    printf "Updating System... "
    sudo pacman -Syyu --noconfirm
    printf "System updated successfully.\n"
}

# Function to install Oh-My-ZSH and ZSH plugins
install_zsh() {
    printf "Configuring ZSH... "
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
    printf "Changing Shell to ZSH... "
    sudo chsh -s "$(which zsh)"
    chsh -s "$(which zsh)"
    printf "Shell changed to ZSH.\n"
}

# Function to move .zshrc
move_zshrc() {
    printf "Copying .zshrc to Home Folder... "
    mv "$HOME"/archinstaller/configs/.zshrc "$HOME"/
    printf ".zshrc copied successfully.\n"
}

# Function to configure locales
configure_locales() {
    printf "Configuring Locales... "
    sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
    printf "Locales generated successfully.\n"
}

# Function to set language locale and timezone
set_language_locale_timezone() {
    printf "Setting Language Locale and Timezone... "
    sudo localectl set-locale LANG="en_US.UTF-8"
    sudo localectl set-locale LC_NUMERIC="el_GR.UTF-8"
    sudo localectl set-locale LC_TIME="el_GR.UTF-8"
    sudo localectl set-locale LC_MONETARY="el_GR.UTF-8"
    sudo localectl set-locale LC_MEASUREMENT="el_GR.UTF-8"
    sudo timedatectl set-timezone "Europe/Athens"
    printf "Language locale and timezone changed successfully.\n"
}

# Function to remove htop package
remove_htop() {
    printf "Removing htop package... "
    sudo pacman -Rcs --noconfirm htop
    printf "htop package removed successfully.\n"
}

# Function to ask for user input to install or skip a program
ask_install_scripts() {
    read -p "Do you want to install $1? (y/n): " confirm_install
    while [[ ! "$confirm_install" =~ ^[yn]$ ]]; do
        read -p "Invalid input. Please enter 'y' to install or 'n' to skip: " confirm_install
    done
    if [[ "$confirm_install" == "y" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to install programs
install_programs() {
    printf "Installing Programs... "
    if ask_install_skip "additional programs"; then
        bash archinstaller/scripts/install_programs.sh
        printf "Programs installed successfully.\n"
    else
        printf "Skipping installation of additional programs.\n"
    fi
}

# Function to install flatpak programs
install_flatpak_programs() {
    printf "Installing Flatpak Programs... "
    if ask_install_skip "Flatpak programs"; then
        bash archinstaller/scripts/install_flatpak_programs.sh
        printf "Flatpak programs installed successfully.\n"
    else
        printf "Skipping installation of Flatpak programs.\n"
    fi
}

# Function to install AUR programs
install_aur_programs() {
    printf "Installing AUR Programs... "
    if ask_install_skip "AUR programs"; then
        bash archinstaller/scripts/install_aur_programs.sh
        printf "AUR programs installed successfully.\n"
    else
        printf "Skipping installation of AUR programs.\n"
    fi
}

# Function to enable services
enable_services() {
    printf "Enabling Services... "
    local services=(
        "fstrim.timer"
        "bluetooth"
        "sshd"
        "fail2ban"
        "paccache.timer"
        "reflector.service"
        "reflector.timer"
        "teamviewerd.service"
        "ufw"
        "cronie"
    )

    for service in "${services[@]}"; do
        sudo systemctl enable --now "$service"
    done

    printf "Services enabled successfully.\n"
}

# Function to create fastfetch config
create_fastfetch_config() {
    printf "Creating fastfetch config... "
    fastfetch --gen-config
    printf "fastfetch config created successfully.\n"
    
    printf "Copying fastfetch config from repository to ~/.config/fastfetch/... "
    cp "$HOME"/archinstaller/configs/config.jsonc "$HOME"/.config/fastfetch/config.jsonc
    printf "fastfetch config copied successfully.\n"
}

# Function to configure firewall
configure_firewall() {
    printf "Configuring Firewall... "
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw logging on
    sudo ufw limit ssh
    sudo ufw allow 1714:1764/tcp
    sudo ufw allow 1714:1764/udp
    sudo ufw --force enable
    printf "Firewall configured successfully.\n"
}

# Function to clear unused packages and cache
clear_unused_packages_cache() {
    printf "Clearing Unused Packages and Cache... "
    sudo pacman -Rns $(pacman -Qdtq) --noconfirm
    sudo pacman -Sc --noconfirm
    yay -Sc --noconfirm
    rm -rf ~/.cache/* && sudo paccache -r
    printf "Unused packages and cache cleared successfully.\n"
}

# Function to delete the archinstaller folder
delete_archinstaller_folder() {
    printf "Deleting Archinstaller Folder... "
    sudo rm -rf "$HOME"/archinstaller
    printf "Archinstaller folder deleted successfully.\n"
}

# Function to reboot system
reboot_system() {
    printf "Rebooting System... "
    printf "Press 'y' to reboot now, or 'n' to cancel.\n"
    
    read -p "Do you want to reboot now? (y/n): " confirm_reboot

    # Validate user input for reboot confirmation
    while [[ ! "$confirm_reboot" =~ ^[yn]$ ]]; do
        read -p "Invalid input. Please enter 'y' to reboot now or 'n' to cancel: " confirm_reboot
    done

    if [[ "$confirm_reboot" == "y" ]]; then
        printf "Rebooting now... "
        sudo reboot
    else
        printf "Reboot canceled. You can reboot manually later by typing 'sudo reboot'.\n"
    fi
}

# Main script

# Run functions
identify_kernel_type
install_kernel_headers
remove_kernel_fallback_image
configure_pacman
make_systemd_boot_silent
change_loader_conf
enable_asterisks_sudo
update_mirrorlist
update_system
install_zsh
change_shell_to_zsh
move_zshrc
configure_locales
set_language_locale_timezone
remove_htop
ask_install_scripts
enable_services
create_fastfetch_config
configure_firewall
clear_unused_packages_cache
delete_archinstaller_folder
reboot_system