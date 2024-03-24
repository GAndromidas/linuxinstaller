#!/bin/bash

# Install GNOME-specific programs
  echo -e "\033[1;34m"
  echo -e "INSTALLING GNOME-SPECIFIC PROGRAMS...\n"
  echo -e "\033[0m"
  sudo pacman -S --needed --noconfirm celluloid gnome-tweaks gufw seahorse transmission-gtk
  sudo pacman -Rcs --noconfirm epiphany gnome-contacts gnome-maps gnome-music gnome-tour htop snapshot totem
  sudo flatpak install -y flathub com.mattjakeman.ExtensionManager net.davidotek.pupgui2 org.gtk.Gtk3theme.adw-gtk3 org.gtk.Gtk3theme.adw-gtk3-dark
  yay -S --needed --noconfirm ocs-url
  echo -e "\033[1;34m"
  echo -e "GNOME-SPECIFIC PROGRAMS INSTALLED SUCCESSFULLY.\n"
  echo -e "\033[0m"

# Download repository, extract, and move to $HOME/.themes
  echo -e "\033[1;34m"
  echo -e "DOWNLOADING THEME AND INSTALLING...\n"
  echo -e "\033[0m"
  mkdir -p $HOME/.themes
  wget https://github.com/lassekongo83/adw-gtk3/releases/download/v5.3/adw-gtk3v5.3.tar.xz -O $HOME/adw-gtk3.tar.xz
  tar -xf $HOME/adw-gtk3.tar.xz -C $HOME/
  mv $HOME/adw-gtk3-dark $HOME/.themes/
  rm -rf $HOME/adw-gtk3
  rm $HOME/adw-gtk3.tar.xz

  echo -e "\033[1;34m"
  echo -e "THEME INSTALLED SUCCESSFULLY.\n"
  echo -e "\033[0m"

# Gnome Enable Minimize, Maximize, Close
  gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"

# Gnome Layout Shift+Alt Fix
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source "['<Shift>Alt_L']"
  gsettings set org.gnome.desktop.wm.keybindings switch-input-source-backward "['<Alt>Shift_L']"

# Gnome Enable VRR (Experimental)
  gsettings set org.gnome.mutter experimental-features "['variable-refresh-rate']"

# Gnome Enable Adw-GTK3-Dark
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' && gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
