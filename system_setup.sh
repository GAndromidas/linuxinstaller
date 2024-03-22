#!/bin/bash

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
