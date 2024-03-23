#!/bin/bash

# Install KDE-specific programs
echo -e "\033[1;34m"
echo -e "INSTALLING KDE-SPECIFIC PROGRAMS...\n"
echo -e "\033[0m"
sudo pacman -S --needed --noconfirm ark gwenview kdeconnect kwalletmanager kvantum okular packagekit-qt6 spectacle qbittorrent
sudo flatpak install -y flathub net.davidotek.pupgui2
echo -e "\033[1;34m"
echo -e "KDE-SPECIFIC PROGRAMS INSTALLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Configure firewall for KDE
echo -e "\033[1;34m"
echo -e "CONFIGURING FIREWALL FOR KDE...\n"
echo -e "\033[0m"
sudo systemctl enable --now ufw

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Allow specific services for KDE
sudo ufw allow 1714:1764/tcp
sudo ufw allow 1714:1764/udp

# Enable logging
sudo ufw logging on

# Enable rate limiting to prevent DoS attacks
sudo ufw limit ssh/tcp

# Enable UFW
sudo ufw --force enable

echo -e "\033[1;34m"
echo -e "FIREWALL CONFIGURED SUCCESSFULLY FOR KDE.\n"
echo -e "\033[0m"
