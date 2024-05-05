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
    noto-fonts
    noto-fonts-extra
    ntfs-3g
    openssh
    os-prober
    pacman-contrib
    samba
    sl
    speedtest-cli
    ttf-hack
    ttf-liberation
    ufw
    unrar
    vkd3d
    xwaylandvideobridge
    # Add or remove programs as needed
)

# Programs to install using yay
yay_programs=(
    dropbox
    pince-git
    spotify
    stremio
    teamviewer
    # Add or remove AUR programs as needed
)

# Essential programs to install using pacman
essential_programs=(
    discord
    fileZilla
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
    vlc
    wine
    qbittorrent
    # Add or remove essential programs as needed
)

# KDE-specific programs to install using pacman
kde_programs=(
    ark
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    packagekit-qt6
    spectacle
    # Add or remove KDE-specific programs as needed
)

# Display ASCII Art
echo -e "\033[1;34m"
echo '    ░█████╗░██████╗░░█████╗░██╗░░██╗██╗███╗░░██╗░██████╗████████╗░█████╗░██╗░░░░░██╗░░░░░███████╗██████╗░'
echo '    ██╔══██╗██╔══██╗██╔══██╗██║░░██║██║████╗░██║██╔════╝╚══██╔══╝██╔══██╗██║░░░░░██║░░░░░██╔════╝██╔══██╗'
echo '    ███████║██████╔╝██║░░╚═╝███████║██║██╔██╗██║╚█████╗░░░░██║░░░███████║██║░░░░░██║░░░░░█████╗░░██████╔╝'
echo '    ██╔══██║██╔══██╗██║░░██╗██╔══██║██║██║╚████║░╚═══██╗░░░██║░░░██╔══██║██║░░░░░██║░░░░░██╔══╝░░██╔══██╗'
echo '    ██║░░██║██║░░██║╚█████╔╝██║░░██║██║██║░╚███║██████╔╝░░░██║░░░██║░░██║███████╗███████╗███████╗██║░░██║'
echo '    ╚═╝░░╚═╝╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝╚═╝╚═╝░░╚══╝╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚══════╝╚══════╝╚══════╝╚═╝░░╚═╝'
echo -e "\033[0m"

# Prompt the user for their password
echo -e "\033[1;34m"
echo
read -s -p "Enter your password: " password
echo
echo -e "\033[0m"

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    LOADER_DIR="/boot/loader"
    ENTRIES_DIR="$LOADER_DIR/entries"
    linux_entry=$(find "$ENTRIES_DIR" -type f -name '*_linux.conf' ! -name '*_linux-fallback.conf')
    if [ -z "$linux_entry" ]; then
        echo "Error: Linux entry not found."
        exit 1
    fi
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"
    echo "Silent boot options added to Linux entry: $(basename "$linux_entry")."
}

# Function to change loader.conf
change_loader_conf() {
    LOADER_CONF="/boot/loader/loader.conf"
    sudo sed -i 's/^timeout.*/timeout 5/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
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
echo -e "\033[1;34m"
echo -e "CONFIGURING PACMAN...\n"
echo -e "\033[0m"
sudo sed -i '/^#Color/s/^#//' /etc/pacman.conf
sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
sudo sed -i '/^#VerbosePkgLists/s/^#//' /etc/pacman.conf
sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
echo -e "\033[1;34m"
echo -e "PACMAN CONFIGURATION UPDATED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Update system
echo -e "\033[1;34m"
echo -e "UPDATING SYSTEM...\n"
echo -e "\033[0m"
sudo pacman -Syyu --noconfirm
sudo pacman -S --needed --noconfirm reflector rsync
echo -e "\033[1;34m"
echo -e "SYSTEM UPDATED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Update mirrorlist
echo -e "\033[1;34m"
echo -e "UPDATING MIRRORLIST...\n"
echo -e "\033[0m"
sudo reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
echo -e "\033[1;34m"
echo -e "MIRRORLIST UPDATED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Install Oh-My-ZSH and ZSH Plugins
echo -e "\033[1;34m"
echo -e "\nINSTALLING ZSH AND CHANGE BASH TO ZSH..."
echo -e "\033[0m"
sudo pacman -S --needed --noconfirm zsh
yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sleep 1  # Wait for 1 seconds
git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
sleep 1  # Wait for 1 seconds
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

# Move .zshrc
echo -e "\033[1;34m"
echo -e "\nCOPYING .ZSHRC TO HOME FOLDER..."
echo -e "\033[0m"
mv /home/"$USER"/archinstaller/.zshrc /home/"$USER"/

# Change Bash Shell to ZSH Shell
echo "$password" | sudo chsh -s "$(which zsh)"  # Change root shell to ZSH non-interactively using provided password
echo "$password" | chsh -s "$(which zsh)" # Change shell to ZSH non-interactively using provided password
echo -e "\033[1;34m"
echo -e "ZSH CONFIGURED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Run system setup script
#echo -e "\033[1;34m"
#echo -e "RUNNING SYSTEM SETUP SCRIPT...\n"
#echo -e "\033[0m"
#chmod +x system_setup.sh
#sudo ./system_setup.sh
#echo -e "\033[1;34m"
#echo -e "SYSTEM SETUP SCRIPT INSTALLED SUCCESSFULLY.\n"
#echo -e "\033[0m"

# Configure locales
echo -e "\033[1;34m"
echo -e "CONFIGURING LOCALES...\n"
echo -e "\033[0m"
sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
echo -e "\033[1;34m"
echo -e "LOCALES GENERATED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Set language locale and timezone
echo -e "\033[1;34m"
echo -e "SETTING LANGUAGE LOCALE AND TIMEZONE...\n"
echo -e "\033[0m"
sudo localectl set-locale LANG="en_US.UTF-8"
sudo localectl set-locale LC_NUMERIC="el_GR.UTF-8"
sudo localectl set-locale LC_TIME="el_GR.UTF-8"
sudo localectl set-locale LC_MONETARY="el_GR.UTF-8"
sudo localectl set-locale LC_MEASUREMENT="el_GR.UTF-8"
sudo timedatectl set-timezone "Europe/Athens"
echo -e "\033[1;34m"
echo -e "LANGUAGE LOCALE AND TIMEZONE CHANGED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Install Yay
echo -e "\033[1;34m"
echo -e "INSTALLING YAY...\n"
echo -e "\033[0m"
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --needed --noconfirm
cd ..
rm -rf yay
echo -e "\033[1;34m"
echo -e "YAY INSTALLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Install AUR packages
echo -e "\033[1;34m"
echo -e "INSTALLING AUR PACKAGES...\n"
echo -e "\033[0m"
yay -S --needed --noconfirm "${yay_programs[@]}"
echo -e "\033[1;34m"
echo -e "AUR PACKAGES INSTALLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Install programs
echo -e "\033[1;34m"
echo -e "INSTALLING PROGRAMS...\n"
echo -e "\033[0m"
sudo pacman -S --needed --noconfirm "${pacman_programs[@]}"
sudo pacman -S --needed --noconfirm "${essential_programs[@]}"
echo -e "\033[1;34m"
echo -e "PROGRAMS INSTALLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Install KDE-specific programs
echo -e "\033[1;34m"
echo -e "INSTALLING KDE-SPECIFIC PROGRAMS...\n"
echo -e "\033[0m"
sudo pacman -S --needed --noconfirm "${kde_programs[@]}"
sudo pacman -Rcs --noconfirm htop
sudo flatpak install -y flathub net.davidotek.pupgui2
echo -e "\033[1;34m"
echo -e "KDE-SPECIFIC PROGRAMS INSTALLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Enable services
echo -e "\033[1;34m"
echo -e "ENABLING SERVICES...\n"
echo -e "\033[0m"
sudo systemctl enable --now fstrim.timer
sudo systemctl enable --now bluetooth
sudo systemctl enable --now sshd
sudo systemctl enable --now fail2ban
sudo systemctl enable --now paccache.timer
sudo systemctl enable --now reflector.service reflector.timer
sudo systemctl enable --now teamviewerd.service
sudo systemctl enable --now ufw
echo -e "\033[1;34m"
echo -e "SERVICES ENABLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Configure firewall
echo -e "\033[1;34m"
echo -e "CONFIGURING FIREWALL...\n"
echo -e "\033[0m"

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
echo -e "\033[1;34m"
echo -e "FIREWALL CONFIGURED SUCCESSFULLY.\n"
echo -e "\033[0m"

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

echo -e "\033[1;34m"
echo -e "CLEARING UNUSED PACKAGES AND CACHE...\n"
echo -e "\033[0m"
sudo pacman -Rns $(pacman -Qdtq) --noconfirm
sudo pacman -Sc --noconfirm
yay -Sc --noconfirm
rm -rf ~/.cache/* && sudo paccache -r
echo -e "\033[1;34m"
echo -e "UNUSED PACKAGES AND CACHE CLEARED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Delete the archinstaller folder
echo -e "\033[1;34m"
echo -e "DELETING ARCHINSTALLER FOLDER...\n"
echo -e "\033[0m"
sudo rm -rf /home/"$USER"/archinstaller
echo -e "\033[1;34m"
echo -e "ARCHINSTALLER FOLDER DELETED SUCCESSFULLY.\n"
echo -e "\033[0m"

echo -e "\033[1;34m"
echo -e "REBOOTING SYSTEM IN 10 SECONDS...\n"
echo -e "PRESS ENTER TO REBOOT NOW, OR CTRL+C TO CANCEL.\n"
echo -e "\033[0m"

for ((i = 10; i > 0; i--)); do
    echo -n "$i "
    sleep 1
done

echo -e "\n\nREBOOTING NOW..."
read -p "Press Enter to reboot now, or Ctrl+C to cancel" input
sudo reboot
