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

# Define log file
LOGFILE="/var/log/archinstaller.log"

# Function to log messages
log() {
    echo "$(date '+%d-%m-%Y %H:%M:%S') - $1" | tee -a $LOGFILE
}

# Configure pacman
log "Configuring Pacman..."
sudo sed -i '/^#Color/s/^#//' /etc/pacman.conf
sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
sudo sed -i '/^#VerbosePkgLists/s/^#//' /etc/pacman.conf
sudo sed -i 's/^#ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
sudo sed -i 's/^ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf
log "Pacman Configuration Updated Successfully."

# Update mirrorlist
log "Updating Mirrorlist..."
sudo pacman -S --needed --noconfirm reflector rsync
sudo reflector --verbose --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy
log "Mirrorlist Updated Successfully."

# Fuction to load files
load_program_lists() {
    if [ -n "$SUDO_USER" ]; then
        home_directory="/home/$SUDO_USER"
    else
        home_directory="$HOME"
    fi
    pacman_programs=($(cat "$home_directory/archinstaller/pacman_programs.txt"))
    yay_programs=($(cat "$home_directory/archinstaller/yay_programs.txt"))
    essential_programs=($(cat "$home_directory/archinstaller/essential_programs.txt"))
    kde_programs=($(cat "$home_directory/archinstaller/kde_programs.txt"))
}

# Function to update system
update_system() {
    log "Updating system..."
    if ! sudo pacman -Syyu --noconfirm; then
        log "Failed to update system. Exiting."
        exit 1
    fi
    log "System updated successfully."
}

# Function to install packages using pacman
install_pacman_packages() {
    log "Installing packages with Pacman..."
    if ! sudo pacman -S --needed --noconfirm "${pacman_programs[@]}" "${essential_programs[@]}" "${kde_programs[@]}"; then
        log "Failed to install packages with Pacman. Exiting."
        exit 1
    fi
    log "Packages installed successfully."
}

# Function to install Yay
install_yay() {
    log "Installing Yay..."
    git clone https://aur.archlinux.org/yay.git
    cd yay || { log "Failed to change directory to yay. Exiting."; exit 1; }
    makepkg -si --needed --noconfirm || { log "Failed to install Yay. Exiting."; exit 1; }
    cd .. && rm -rf yay || { log "Failed to clean up Yay files. Exiting."; exit 1; }
    echo -e "Yay installed successfully."
}

# Function to install AUR packages using Yay
install_yay_packages() {
    log "Installing AUR packages with Yay..."
    if ! yay -S --needed --noconfirm "${yay_programs[@]}"; then
        log "Failed to install AUR packages with Yay. Exiting."
        exit 1
    fi
    log "AUR packages installed successfully."
}

# Main execution flow
main() {
    log "Starting script execution..."
    load_program_lists
    update_system
    install_pacman_packages
    install_yay
    install_yay_packages
    log "Script execution completed successfully."
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log "This script must be run as root. Please use sudo."
    exit 1
fi

main

# Function to make Systemd-Boot silent
make_systemd_boot_silent() {
    LOADER_DIR="/boot/loader"
    ENTRIES_DIR="$LOADER_DIR/entries"

    # Find the Linux or Linux-zen entry
    linux_entry=$(find "$ENTRIES_DIR" -type f \( -name '*_linux.conf' -o -name '*_linux-zen.conf' \) ! -name '*_linux-fallback.conf' -print -quit)

    if [ -z "$linux_entry" ]; then
        log "Error: Linux entry not found."
        exit 1
    fi

    # Add silent boot options to the Linux entry
    sudo sed -i '/options/s/$/ quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3/' "$linux_entry"

    log "Silent boot options added to Linux entry: $(basename "$linux_entry")."
}

# Function to change loader.conf
change_loader_conf() {
    LOADER_CONF="/boot/loader/loader.conf"
    sudo sed -i 's/^timeout.*/timeout 5/' "$LOADER_CONF"
    sudo sed -i 's/^#console-mode.*/console-mode max/' "$LOADER_CONF"
    log "Loader configuration updated."
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    if grep -q '^Defaults.*pwfeedback' /etc/sudoers; then
        log "Asterisks for password feedback is already enabled in sudoers."
    else
        echo "Enabling asterisks for password feedback in sudoers..."
        echo 'Defaults        pwfeedback' | sudo tee -a /etc/sudoers > /dev/null
        log "Asterisks for password feedback enabled successfully."
    fi
}

# Main script execution
make_systemd_boot_silent
change_loader_conf
enable_asterisks_sudo

main

# Install Oh-My-ZSH and ZSH Plugins
log "Configuring ZSH..."
sudo pacman -S --needed --noconfirm zsh
yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sleep 1  # Wait for 1 second
git clone https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
sleep 1  # Wait for 1 second
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
log "ZSH Configured Successfully."

# Change Bash Shell to ZSH Shell
sudo chsh -s "$(which zsh)"  # Change root shell to ZSH non-interactively using provided password
chsh -s "$(which zsh)" # Change shell to ZSH non-interactively using provided password
log "Shell changed to ZSH."

# Move .zshrc
log "Copying .zshrc to Home Folder..."
mv ~/"$USER"/archinstaller/.zshrc /home/"$USER"/
log ".zshrc Copied Successfully."

# Configure locales
log "Configuring Locales..."
sudo sed -i 's/#el_GR.UTF-8 UTF-8/el_GR.UTF-8 UTF-8/' /etc/locale.gen
sudo locale-gen
log "Locales Generated Successfully."

# Set language locale and timezone
log "Setting Language Locale and Timezone..."
sudo localectl set-locale LANG="en_US.UTF-8"
sudo localectl set-locale LC_NUMERIC="el_GR.UTF-8"
sudo localectl set-locale LC_TIME="el_GR.UTF-8"
sudo localectl set-locale LC_MONETARY="el_GR.UTF-8"
sudo localectl set-locale LC_MEASUREMENT="el_GR.UTF-8"
sudo timedatectl set-timezone "Europe/Athens"
log "Language Locale and Timezone Changed Successfully."

# Enable services
log "Enabling Services..."
sudo systemctl enable --now fstrim.timer
sudo systemctl enable --now bluetooth
sudo systemctl enable --now sshd
sudo systemctl enable --now fail2ban
sudo systemctl enable --now paccache.timer
sudo systemctl enable --now reflector.service reflector.timer
sudo systemctl enable --now teamviewerd.service
sudo systemctl enable --now ufw
log "Services Enabled Successfully."

# Configure firewall
log "Configuring Firewall..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw logging on
sudo ufw limit ssh
sudo ufw allow 1714:1764/tcp
sudo ufw allow 1714:1764/udp
sudo ufw --force enable
log "Firewall Configured Successfully."

# Edit jail.local for Fail2Ban
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
sudo systemctl restart fail2ban
log "Fail2Ban configured and restarted."

# Clear Unused Packages and Cache
log "Clearing Unused Packages and Cache..."
sudo pacman -Rns $(pacman -Qdtq) --noconfirm
sudo pacman -Sc --noconfirm
yay -Sc --noconfirm
rm -rf ~/.cache/* && sudo paccache -r
log "Unused Packages and Cache Cleared Successfully."

# Delete the archinstaller folder
log "Deleting Archinstaller Folder..."
sudo rm -rf ~/"$USER"/archinstaller/
log "Archinstaller Folder Deleted Successfully."

# Reboot System
log "Rebooting System..."
echo -e "Press 'y' to reboot now, or 'n' to cancel.\n"
read -p "Do you want to reboot now? (y/n): " confirm_reboot
if [[ "$confirm_reboot" == "y" ]]; then
log "Rebooting Now..."
sudo reboot
else
log "Reboot canceled. You can reboot manually later by typing 'sudo reboot'."
log "Reboot canceled by user."
fi
