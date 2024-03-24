#!/bin/bash

# Install GNOME-specific programs
echo -e "\033[1;34m"
echo -e "INSTALLING GNOME-SPECIFIC PROGRAMS...\n"
echo -e "\033[0m"
sudo pacman -S --needed --noconfirm gnome-tweaks gufw transmission-gtk
sudo pacman -Rcs --noconfirm epiphany gnome-contacts gnome-music gnome-tour htop snapshot totem
sudo flatpak install -y flathub com.mattjakeman.ExtensionManager net.davidotek.pupgui2
yay -S --needed --noconfirm ocs-url
echo -e "\033[1;34m"
echo -e "GNOME-SPECIFIC PROGRAMS INSTALLED SUCCESSFULLY.\n"
echo -e "\033[0m"

# Gnome Enable Minimize, Maximize, Close
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

# Gnome Layout Shift+Alt Fix
gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Shift>Alt_L']"
gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_L']"

# Gnome Enable VRR (Experimental)
gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']"
