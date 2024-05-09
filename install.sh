#!/bin/bash

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
    samba
    sl
    speedtest-cli
    ttf-liberation
    ufw
    unrar
    vkd3d
    vulkan-radeon
    wlroots
    xwaylandvideobridge
    # Add or remove programs as needed
)

# Programs to install using yay
yay_programs=(
    dropbox
    spotify
    stremio
    teamviewer
    # Add or remove AUR programs as needed
)

# Essential programs to install using pacman
essential_programs=(
    discord
    filezilla
    firefox
    gimp
    kdenlive
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

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    LOADER_DIR="/boot/loader"
    ENTRIES_DIR="$LOADER_DIR/entries"
    
    # Find the Linux or Linux-zen entry
    linux_entry=$(find "$ENTRIES_DIR" -type f \( -name '*_linux.conf' -o -name '*_linux-zen.conf' \) ! -name '*_linux-fallback.conf' -print -quit)
    
    if [ -z "$linux_entry" ]; then
       echo "Error: Linux entry not found."
        exit 1
    fi
    
    # Add silent boot options to the Linux entry
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"
    
    echo "Silent boot options added to Linux entry: $(basename "$linux_entry")."
}

# Function to change loader.conf
change_loader_conf() {
    LOADER_CONF="/boot/loader/loader.conf"
    sudo sed -i 's/^timeout.*/timeout 5/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    echo "Loader configuration updated."
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    if grep -q '^Defaults.*pwfeedback' /etc/sudoers; then
        echo "Asterisks for password feedback is already enabled in sudoers."
    else
        echo "Enabling asterisks for password feedback in sudoers..."
        echo 'Defaults        pwfeedback' | sudo tee -a /etc/sudoers > /dev/null
        echo "Asterisks for password feedback enabled successfully."
    fi
}

# Main script
make_systemd_boot_silent
change_loader_conf
enable_asterisks_sudo

# Configure pacman
echo "Configuring Pacman..."
sudo sed -i '/^#Color/s/^#//' /etc/pacman.conf
sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
sudo sed -i '/^#VerbosePkgLists/s/^#//' /etc/pacman.conf
sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
echo "Pacman Configuration Updated Successfully."

# Update system
echo "Updating System..."
sudo pacman -Syyu --noconfirm
sudo pacman -S --needed --noconfirm reflector rsync
echo "System Updated Successfully."

# Update mirrorlist
echo "Updating Mirrorlist..."
sudo reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
echo "Mirrorlist Updated Successfully."

# Install Oh-My-ZSH and ZSH Plugins
echo "Configuring ZSH..."
sudo pacman -S --needed --noconfirm zsh
yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sleep 1  # Wait for 1 second
git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
sleep 1  # Wait for 1 second
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
echo "ZSH Configured Successfully."

# Change Bash Shell to ZSH Shell
sudo chsh -s "$(which zsh)"  # Change root shell to ZSH non-interactively using provided password
chsh -s "$(which zsh)" # Change shell to ZSH non-interactively using provided password
echo "Shell changed to ZSH."

# Move .zshrc
echo "Copying .zshrc to Home Folder..."
mv /home/"$USER"/archinstaller/.zshrc /home/"$USER"/
echo ".zshrc Copied Successfully."

# Configure locales
echo "Configuring Locales..."
sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
echo "Locales Generated Successfully."

# Set language locale and timezone
echo "Setting Language Locale and Timezone..."
sudo localectl set-locale LANG="en_US.UTF-8"
sudo localectl set-locale LC_NUMERIC="el_GR.UTF-8"
sudo localectl set-locale LC_TIME="el_GR.UTF-8"
sudo localectl set-locale LC_MONETARY="el_GR.UTF-8"
sudo localectl set-locale LC_MEASUREMENT="el_GR.UTF-8"
sudo timedatectl set-timezone "Europe/Athens"
echo "Language Locale and Timezone Changed Successfully."

# Install programs
echo "Installing Programs..."
sudo pacman -S --needed --noconfirm "${pacman_programs[@]}"
sudo pacman -S --needed --noconfirm "${essential_programs[@]}"
echo "Programs Installed Successfully."

# Install KDE-specific programs
echo "Installing KDE-Specific Programs..."
sudo pacman -S --needed --noconfirm "${kde_programs[@]}"
sudo pacman -Rcs --noconfirm htop
sudo flatpak install -y flathub net.davidotek.pupgui2
sudo flatpak upgrade
echo "KDE-Specific Programs Installed Successfully."

# Install Yay
echo "Installing YAY..."
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --needed --noconfirm
cd ..
rm -rf yay
echo "YAY Installed Successfully."

# Install AUR packages
echo "Installing AUR Packages..."
yay -S --needed --noconfirm "${yay_programs[@]}"
echo "AUR Packages Installed Successfully."

# Enable services
echo "Enabling Services..."
sudo systemctl enable --now fstrim.timer
sudo systemctl enable --now bluetooth
sudo systemctl enable --now sshd
sudo systemctl enable --now fail2ban
sudo systemctl enable --now paccache.timer
sudo systemctl enable --now reflector.service reflector.timer
sudo systemctl enable --now teamviewerd.service
sudo systemctl enable --now ufw
echo "Services Enabled Successfully."

# Configure firewall
echo "Configuring Firewall..."

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Enable logging
sudo ufw logging on

# Enable rate limiting to prevent DoS attacks
sudo ufw limit ssh

# Allow KDE Connect ports
sudo ufw allow 1714:1764/tcp
sudo ufw allow 1714:1764/udp

# Enable UFW
sudo ufw --force enable
echo "Firewall Configured Successfully."

# Edit jail.local
sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime = 300
ignoreip = 127.0.0.1
EOF

# Restart Fail2Ban
sudo systemctl restart fail2ban

# Clear Unused Packages and Cache
echo "Clearing Unused Packages and Cache..."
sudo pacman -Rns $(pacman -Qdtq) --noconfirm
sudo pacman -Sc --noconfirm
yay -Sc --noconfirm
rm -rf ~/.cache/* && sudo paccache -r
echo "Unused Packages and Cache Cleared Successfully."

# Delete the archinstaller folder
echo "Deleting Archinstaller Folder..."
sudo rm -rf /home/"$USER"/archinstaller
echo "Archinstaller Folder Deleted Successfully."

# Reboot System
echo "Rebooting System..."
echo -e "Press 'y' to reboot now, or 'n' to cancel.\n"
read -p "Do you want to reboot now? (y/n): " confirm_reboot

if [[ "$confirm_reboot" == "y" ]]; then
    echo "Rebooting Now..."
    sudo reboot
else
    echo "Reboot canceled. You can reboot manually later by typing 'sudo reboot'."
fi
