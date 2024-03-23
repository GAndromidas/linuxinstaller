#!/bin/bash

# Install GNOME-specific programs
sudo pacman -S --needed --noconfirm gnome-tweaks gufw transmission-gtk
sudo pacman -Rcs --needed --noconfirm epiphany gnome-contacts gnome-music gnome-tour snapshot totem
sudo flatpak install -y flathub com.mattjakeman.ExtensionManager net.davidotek.pupgui2

# Configure firewall for GNOME
echo -e "\033[1;34m"
echo -e "CONFIGURING FIREWALL FOR GNOME...\n"
echo -e "\033[0m"
sudo systemctl enable --now ufw

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Enable logging
sudo ufw logging on

# Enable rate limiting to prevent DoS attacks
sudo ufw limit ssh/tcp

# Enable UFW
sudo ufw --force enable

echo -e "\033[1;34m"
echo -e "FIREWALL CONFIGURED SUCCESSFULLY FOR GNOME.\n"
echo -e "\033[0m"

# Gnome Layout Shift+Alt Fix
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Shift>Alt_L']"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_L']"
