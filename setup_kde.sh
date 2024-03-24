#!/bin/bash

# Install KDE-specific programs
  echo -e "\033[1;34m"
  echo -e "INSTALLING KDE-SPECIFIC PROGRAMS...\n"
  echo -e "\033[0m"
  sudo pacman -S --needed --noconfirm ark gwenview kdeconnect kwalletmanager kvantum okular packagekit-qt6 spectacle qbittorrent
  sudo pacman -Rcs --noconfirm htop
  sudo flatpak install -y flathub net.davidotek.pupgui2
  echo -e "\033[1;34m"
  echo -e "KDE-SPECIFIC PROGRAMS INSTALLED SUCCESSFULLY.\n"
  echo -e "\033[0m"

# Configure firewall for KDE
  echo -e "\033[1;34m"
  echo -e "CONFIGURING FIREWALL FOR KDE...\n"
  echo -e "\033[0m"

# Allow KDE Connect ports
  sudo ufw allow 1714:1764/tcp
  sudo ufw allow 1714:1764/udp

  echo -e "\033[1;34m"
  echo -e "FIREWALL CONFIGURED SUCCESSFULLY FOR KDE.\n"
  echo -e "\033[0m"
