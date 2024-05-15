#!/bin/bash

# Function to identify the installed Linux kernel type
identify_kernel_type() {
    printf "Identifying installed Linux kernel type... "

    # Check if linux-zen kernel is installed
    if pacman -Q linux-zen &>/dev/null; then
        printf "Linux-Zen kernel found.\n"
        kernel_headers="linux-zen-headers"
    else
        printf "Standard Linux kernel found.\n"
        kernel_headers="linux-headers"
    fi
}

# Function to install kernel headers
install_kernel_headers() {
    printf "Installing kernel headers... "
    sudo pacman -S --needed --noconfirm "$kernel_headers"
    printf "Kernel headers installed successfully.\n"
}

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
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
    printf "Changing loader.conf... "
    LOADER_CONF="/boot/loader/loader.conf"
    sudo sed -i 's/^timeout.*/timeout 5/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    printf "Loader configuration updated.\n"
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    printf "Enabling asterisks for password in sudoers... "
    if grep -q '^Defaults.*pwfeedback' /etc/sudoers; then
        printf "Asterisks for password feedback is already enabled in sudoers.\n"
    else
        echo 'Defaults        pwfeedback' | sudo tee -a /etc/sudoers > /dev/null
        printf "Asterisks for password feedback enabled successfully.\n"
    fi
}

# Function to configure Pacman
configure_pacman() {
    printf "Configuring Pacman... "
    sudo sed -i '/^#Color/s/^#//' /etc/pacman.conf
    sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
    sudo sed -i '/^#VerbosePkgLists/s/^#//' /etc/pacman.conf
    sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    sudo sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
    printf "Pacman configuration updated successfully.\n"
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
    mv /home/"$USER"/archinstaller/.zshrc /home/"$USER"/
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

# Function to install programs
install_programs() {
    printf "Installing Programs... "
    sudo pacman -S --needed --noconfirm "${pacman_programs[@]}"
    sudo pacman -S --needed --noconfirm "${essential_programs[@]}"
    printf "Programs installed successfully.\n"
}

# Function to install KDE-specific programs
install_kde_programs() {
    printf "Installing KDE-Specific Programs... "
    sudo pacman -S --needed --noconfirm "${kde_programs[@]}"
    sudo pacman -Rcs --noconfirm htop
    sudo flatpak install -y flathub net.davidotek.pupgui2
    sudo flatpak upgrade
    printf "KDE-Specific programs installed successfully.\n"
}

# Function to install YAY
install_yay() {
    printf "Installing YAY... "
    git clone https://aur.archlinux.org/yay.git
    cd yay || exit
    makepkg -si --needed --noconfirm
    cd ..
    rm -rf yay
    printf "YAY installed successfully.\n"
}

# Function to install AUR packages
install_aur_packages() {
    printf "Installing AUR Packages... "
    yay -S --needed --noconfirm "${yay_programs[@]}"
    printf "AUR Packages installed successfully.\n"
}

# Function to enable services
enable_services() {
    printf "Enabling Services... "
    sudo systemctl enable --now fstrim.timer # For SSD Trim
    sudo systemctl enable --now bluetooth # For Bluetooth
    sudo systemctl enable --now sshd # For SSH
    sudo systemctl enable --now fail2ban # For Fail2ban
    sudo systemctl enable --now paccache.timer # For Paccache
    sudo systemctl enable --now reflector.service reflector.timer # For Reflector
    sudo systemctl enable --now teamviewerd.service # For Teamviewer
    sudo systemctl enable --now ufw # For UFW Firewall
    sudo systemctl enable --now cronie # For Timeshift
    printf "Services enabled successfully.\n"
}

# Function to create fastfetch config
create_fastfetch_config() {
    printf "Creating fastfetch config... "
    fastfetch --gen-config
    printf "fastfetch config created successfully.\n"
    
    printf "Copying fastfetch config from repository to ~/.config/fastfetch/... "
    cp /home/"$USER"/archinstaller/config.jsonc /home/"$USER"/.config/fastfetch/config.jsonc
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

# Function to remove Linux kernel fallback image
remove_kernel_fallback_image() {
    printf "Removing Linux kernel fallback image... "
    sudo rm /boot/*fallback*
    printf "Linux kernel fallback image removed successfully.\n"
}

# Function to delete the archinstaller folder
delete_archinstaller_folder() {
    printf "Deleting Archinstaller Folder... "
    sudo rm -rf /home/"$USER"/archinstaller
    printf "Archinstaller folder deleted successfully.\n"
}

# Function to reboot system
reboot_system() {
    printf "Rebooting System... "
    printf "Press 'y' to reboot now, or 'n' to cancel.\n"
    read -p "Do you want to reboot now? (y/n): " confirm_reboot

    if [[ "$confirm_reboot" == "y" ]]; then
        printf "Rebooting now... "
        sudo reboot
    else
        printf "Reboot canceled. You can reboot manually later by typing 'sudo reboot'.\n"
    fi
}

# Main script

# Programs to install using pacman
pacman_programs=(
    android-tools
    bleachbit
    btop
    cmatrix
    dosfstools
    fail2ban
    fastfetch
    flatpak
    fwupd
    gamemode
    gamescope
    hwinfo
    inxi
    lib32-gamemode
    lib32-mangohud
    lib32-vkd3d
    lib32-vulkan-radeon
    mangohud
    net-tools
    noto-fonts-extra
    ntfs-3g
    os-prober
    pacman-contrib
    powerline-fonts
    samba
    sl
    speedtest-cli
    ttf-hack-nerd
    ttf-liberation
    ufw
    unrar
    vkd3d
    vulkan-radeon
    wlroots
    xdg-desktop-portal-gtk
    xwaylandvideobridge
    # Add or remove programs as needed
)

# Essential programs to install using pacman
essential_programs=(
    discord
    filezilla
    firefox
    gimp
    libreoffice-fresh
    lutris
    obs-studio
    openrgb
    smplayer
    steam
    telegram-desktop
    timeshift
    vlc
    wine
    qbittorrent
    # Add or remove essential programs as needed
)

# KDE-specific programs to install using pacman
kde_programs=(
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    packagekit-qt6
    spectacle
    # Add or remove KDE-specific programs as needed
)

# Programs to install using yay
yay_programs=(
    dropbox
    spotify
    stremio
    teamviewer
    # Add or remove AUR programs as needed
)

# Run functions
identify_kernel_type
install_kernel_headers
make_systemd_boot_silent
change_loader_conf
enable_asterisks_sudo
configure_pacman
update_mirrorlist
update_system
install_zsh
change_shell_to_zsh
move_zshrc
configure_locales
set_language_locale_timezone
install_programs
install_kde_programs
install_yay
install_aur_packages
enable_services
create_fastfetch_config
configure_firewall
clear_unused_packages_cache
remove_kernel_fallback_image
delete_archinstaller_folder
reboot_system
