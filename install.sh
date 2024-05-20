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
        echo "\033[0;32m "Kernel headers installed successfully.\033[0m"\n"
    fi
}

# Function to remove Linux kernel fallback image
remove_kernel_fallback_image() {
    echo
    printf "Removing Linux kernel fallback image... "
    echo
    sudo rm /boot/loader/entries/*fallback*
    echo
    printf "\033[0;32m "Linux kernel fallback image removed successfully.\033[0m"\n"
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
        printf "\033[0;32m "Pacman configuration updated successfully.\033[0m"\n"
    fi
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
    printf "\033[0;32m "Loader configuration updated.\033[0m"\n"
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    # Enables password feedback with asterisks in sudoers file.
    echo
    printf "Defaults env_reset,pwfeedback" | sudo EDITOR='tee -a' visudo
    echo
    printf "\033[0;32m  "Password feedback enabled in sudoers.\033[0m"\n"
}

# Function to update mirrorlist
update_mirrorlist() {
    echo
    printf "Updating Mirrorlist... "
    echo
    sudo pacman -S --needed --noconfirm reflector rsync
    sudo reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
    echo
    printf "\033[0;32m "Mirrorlist updated successfully.\033[0m"\n"
}

# Function to update the system
update_system() {
    echo
    printf "Updating System... "
    echo
    sudo pacman -Syyu --noconfirm
    echo
    printf "\033[0;32m "System updated successfully.\033[0m"\n"
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
    printf "\033[0;32m "ZSH configured successfully.\033[0m"\n"
}

# Function to change shell to ZSH
change_shell_to_zsh() {
    echo
    printf "Changing Shell to ZSH... "
    echo
    sudo chsh -s "$(which zsh)"
    chsh -s "$(which zsh)"
    echo
    printf "\033[0;32m "Shell changed to ZSH.\033[0m"\n"
}

# Function to move .zshrc
move_zshrc() {
    echo
    printf "Copying .zshrc to Home Folder... "
    echo
    mv "$HOME"/archinstaller/configs/.zshrc "$HOME"/
    echo
    printf "\033[0;32m ".zshrc copied successfully.\033[0m"\n"
}

# Function to configure locales
configure_locales() {
    echo
    printf "Configuring Locales... "
    echo
    sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
    echo
    printf "\033[0;32m "Locales generated successfully.\033[0m"\n"
}

# Function to set language locale and timezone
set_language_locale_timezone() {
    echo
    printf "Setting Language Locale and Timezone... "
    echo
    sudo localectl set-locale LANG="en_US.UTF-8"
    sudo localectl set-locale LC_NUMERIC="el_GR.UTF-8"
    sudo localectl set-locale LC_TIME="el_GR.UTF-8"
    sudo localectl set-locale LC_MONETARY="el_GR.UTF-8"
    sudo localectl set-locale LC_MEASUREMENT="el_GR.UTF-8"
    sudo timedatectl set-timezone "Europe/Athens"
    echo
    printf "\033[0;32m "Language locale and timezone changed successfully.\033[0m"\n"
}

# Function to remove htop package
remove_htop() {
    echo
    printf "Removing htop package... "
    echo
    sudo pacman -Rcs --noconfirm htop
    echo
    printf "\033[0;32m "htop package removed successfully.\033[0m"\n"
}

# Function to choose between YAY and Paru for installation
choose_yay_or_paru() {
    echo
    printf "Choose AUR Helper: YAY or Paru\n"
    echo
    read -p "Enter 'y' for YAY or 'p' for Paru: " aur_helper

    # Validate user input for AUR helper selection
    while [[ ! "$aur_helper" =~ ^[yp]$ ]]; do
        read -p "Invalid input. Please enter 'y' for YAY or 'p' for Paru: " aur_helper
    done

    if [[ "$aur_helper" == "y" ]]; then
        install_yay
    elif [[ "$aur_helper" == "p" ]]; then
        install_paru
    fi
}

# Function to install YAY
install_yay() {
    echo
    printf "Installing YAY... "
    echo
    if [ -d "yay" ]; then
        rm -rf yay
    fi

    git clone https://aur.archlinux.org/yay.git
    cd yay || { echo "Error: Unable to change directory to yay. Exiting."; exit 1; }

    if ! makepkg -si --needed --noconfirm; then
        echo "Error: Failed to install YAY. Exiting."
        exit 1
    fi

    cd ..
    rm -rf yay
    echo
    printf "\033[0;32m "YAY installed successfully.\033[0m"\n"
}

# Function to install Paru
install_paru() {
    echo
    printf "Installing Paru... "
    echo
    if [ -d "paru" ]; then
        rm -rf paru
    fi

    git clone https://aur.archlinux.org/paru.git
    cd paru || { echo "Error: Unable to change directory to paru. Exiting."; exit 1; }

    if ! makepkg -si --needed --noconfirm; then
        echo "Error: Failed to install Paru. Exiting."
        exit 1
    fi

    cd ..
    rm -rf paru
    echo
    printf "\033[0;32m "Paru installed successfully.\033[0m"\n"
}

# Function to install programs
install_programs() {
    echo
    printf "Installing Programs... "
    echo
    (cd "$HOME/archinstaller/scripts" && ./install_programs.sh)
    echo
    printf "\033[0;32m "Programs installed successfully.\033[0m"\n"
    
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
    printf "\033[0;32m "Flatpak programs installed successfully.\033[0m"\n"
    
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
    printf "\033[0;32m "AUR programs installed successfully.\033[0m"\n"
}

# Function to enable services
enable_services() {
    echo
    printf "Enabling Services... "
    echo
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
    
    echo
    printf "\033[0;32m "Services enabled successfully.\033[0m"\n"
}

# Function to create fastfetch config
create_fastfetch_config() {
    echo
    printf "Creating fastfetch config... "
    echo
    fastfetch --gen-config
    echo
    printf "\033[0;32m "fastfetch config created successfully.\033[0m"\n"
    
    echo
    printf "Copying fastfetch config from repository to ~/.config/fastfetch/... "
    echo
    cp "$HOME"/archinstaller/configs/config.jsonc "$HOME"/.config/fastfetch/config.jsonc
    echo
    printf "\033[0;32m "fastfetch config copied successfully.\033[0m"\n"
}

# Function to configure firewall
configure_firewall() {
    echo
    printf "Configuring Firewall... "
    echo
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    sudo ufw logging on
    sudo ufw limit ssh
    sudo ufw allow 1714:1764/tcp
    sudo ufw allow 1714:1764/udp
    sudo ufw --force enable
    echo
    printf "\033[0;32m "Firewall configured successfully.\033[0m"\n"
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
    printf "\033[0;32m "Unused packages and cache cleared successfully.\033[0m"\n"
}

# Function to delete the archinstaller folder
delete_archinstaller_folder() {
    echo
    printf "Deleting Archinstaller Folder... "
    echo
    sudo rm -rf "$HOME"/archinstaller
    echo
    printf "\033[0;32m "Archinstaller folder deleted successfully.\033[0m"\n"
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
choose_yay_or_paru
install_programs
enable_services
create_fastfetch_config
configure_firewall
clear_unused_packages_cache
delete_archinstaller_folder
reboot_system