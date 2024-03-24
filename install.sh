#!/bin/bash

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
    sudo reflector --verbose --country Greece --age 24 --latest 5 --protocol https,http --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
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
    echo -e "\033[1;34m"
    echo -e "RUNNING SYSTEM SETUP SCRIPT...\n"
    echo -e "\033[0m"
    chmod +x system_setup.sh
    sudo ./system_setup.sh
    echo -e "\033[1;34m"
    echo -e "SYSTEM SETUP SCRIPT INSTALLED SUCCESSFULLY.\n"
    echo -e "\033[0m"

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
    yay -S --needed --noconfirm dropbox heroic-games-launcher-bin spotify stremio teamviewer
    echo -e "\033[1;34m"
    echo -e "AUR PACKAGES INSTALLED SUCCESSFULLY.\n"
    echo -e "\033[0m"

# Install programs
    echo -e "\033[1;34m"
    echo -e "INSTALLING ESSENTIAL PROGRAMS...\n"
    echo -e "\033[0m"
    sudo pacman -S --needed --noconfirm android-tools bleachbit btop cmatrix dosfstools eza fail2ban fastfetch flatpak fwupd gamemode hwinfo inxi lib32-gamemode lib32-vulkan-radeon net-tools noto-fonts noto-fonts-extra ntfs-3g openssh os-prober pacman-contrib samba sl speedtest-cli ttf-liberation ufw unrar

# Essential programs
    sudo pacman -S --needed --noconfirm discord filezilla firefox gimp libreoffice-fresh lutris obs-studio openrgb smplayer steam telegram-desktop vlc wine
    echo -e "\033[1;34m"
    echo -e "ESSENTIAL PROGRAMS INSTALLED SUCCESSFULLY.\n"
    echo -e "\033[0m"

# Enable services
    echo -e "\033[1;34m"
    echo -e "ENABLING SERVICES...\n"
    echo -e "\033[0m"
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

# Check if GNOME is installed
    if pacman -Qs gnome-shell &> /dev/null; then
    echo "GNOME detected."
    chmod +x setup_gnome.sh
    ./setup_gnome.sh

# Check if KDE is installed
    elif pacman -Qs plasma-desktop &> /dev/null; then
    echo "KDE detected."
    chmod +x setup_kde.sh
    ./setup_kde.sh
    fi

# Delete the archinstaller folder
    echo -e "\033[1;34m"
    echo -e "DELETING ARCHINSTALLER FOLDER...\n"
    echo -e "\033[0m"
    sudo rm -rf /home/"$USER"/archinstaller
    echo -e "\033[1;34m"
    echo -e "ARCHINSTALLER FOLDER DELETED SUCCESSFULLY.\n"
    echo -e "\033[0m"

# Reboot system with a countdown and cancel option
    echo -e "\033[1;34m"
    echo -e "REBOOTING SYSTEM IN 10 SECONDS...\n"
    echo -e "PRESS ENTER TO REBOOT NOW, OR CTRL+C TO CANCEL.\n"
    echo -e "\033[0m"

    for ((i = 10; i > 0; i--)); do
        echo -n "$i "
        sleep 1
    done

    echo -e "\n\nREBOOTING NOW..."
    sudo reboot
