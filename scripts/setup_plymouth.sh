#!/bin/bash

# Plymouth Setup Script for Arch Linux with systemd-boot
# This script configures Plymouth with the Arch Linux logo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_error "This script should not be run as root. Run as regular user with sudo access."
    exit 1
fi

# Check if systemd-boot is being used
if [[ ! -d /boot/loader ]]; then
    print_error "systemd-boot not detected. This script is designed for systemd-boot systems."
    exit 1
fi

print_status "Starting Plymouth configuration for Arch Linux..."

# Install Plymouth if not already installed
print_status "Checking Plymouth installation..."
if ! pacman -Qi plymouth &>/dev/null; then
    print_status "Installing Plymouth..."
    sudo pacman -S --needed plymouth
else
    print_success "Plymouth is already installed"
fi

# Find systemd-boot entries
print_status "Scanning for systemd-boot entries..."
BOOT_ENTRIES_DIR="/boot/loader/entries"

if [[ ! -d "$BOOT_ENTRIES_DIR" ]]; then
    print_error "Boot entries directory not found at $BOOT_ENTRIES_DIR"
    exit 1
fi

# Find kernel entries
LINUX_ENTRIES=$(find "$BOOT_ENTRIES_DIR" -name "*.conf" -exec grep -l "linux.*vmlinuz-linux" {} \; 2>/dev/null)
ZEN_ENTRIES=$(find "$BOOT_ENTRIES_DIR" -name "*.conf" -exec grep -l "linux.*vmlinuz-linux-zen" {} \; 2>/dev/null)

print_status "Found boot entries:"
echo
if [[ -n "$LINUX_ENTRIES" ]]; then
    echo -e "${GREEN}Linux kernel entries:${NC}"
    for entry in $LINUX_ENTRIES; do
        entry_name=$(basename "$entry" .conf)
        echo "  - $entry_name ($(basename "$entry"))"
    done
fi

if [[ -n "$ZEN_ENTRIES" ]]; then
    echo -e "${GREEN}Linux Zen kernel entries:${NC}"
    for entry in $ZEN_ENTRIES; do
        entry_name=$(basename "$entry" .conf)
        echo "  - $entry_name ($(basename "$entry"))"
    done
fi

if [[ -z "$LINUX_ENTRIES" && -z "$ZEN_ENTRIES" ]]; then
    print_error "No Linux or Linux Zen kernel entries found!"
    exit 1
fi

echo

# Set Plymouth theme to default Arch theme
print_status "Setting Plymouth theme to 'bgrt' (shows vendor logo - Arch on most systems)..."
sudo plymouth-set-default-theme bgrt

# Alternative themes available:
print_status "Available Plymouth themes:"
plymouth-list-themes | while read theme; do
    echo "  - $theme"
done

# Function to update boot entry
update_boot_entry() {
    local entry_file="$1"
    local entry_name=$(basename "$entry_file" .conf)

    print_status "Updating boot entry: $entry_name"

    # Create backup
    sudo cp "$entry_file" "$entry_file.backup"

    # Check if plymouth is already in options
    if grep -q "plymouth" "$entry_file"; then
        print_warning "Plymouth options already present in $entry_name, skipping..."
        return
    fi

    # Add plymouth to boot options
    sudo sed -i '/^options/ s/$/ splash plymouth.ignore-serial-consoles/' "$entry_file"

    print_success "Updated $entry_name"
}

# Update all found entries
print_status "Updating boot entries with Plymouth options..."

for entry in $LINUX_ENTRIES $ZEN_ENTRIES; do
    update_boot_entry "$entry"
done

# Update mkinitcpio configuration
print_status "Updating mkinitcpio configuration..."
MKINITCPIO_CONF="/etc/mkinitcpio.conf"

# Backup mkinitcpio.conf
sudo cp "$MKINITCPIO_CONF" "$MKINITCPIO_CONF.backup"

# Check if plymouth hook is already present
if grep -q "plymouth" "$MKINITCPIO_CONF"; then
    print_warning "Plymouth hook already present in mkinitcpio.conf"
else
    # Add plymouth hook after base and udev
    sudo sed -i '/^HOOKS=/ s/udev/udev plymouth/' "$MKINITCPIO_CONF"
    print_success "Added Plymouth hook to mkinitcpio.conf"
fi

# Regenerate initramfs for all installed kernels
print_status "Regenerating initramfs..."

if pacman -Qi linux &>/dev/null; then
    print_status "Regenerating initramfs for linux kernel..."
    sudo mkinitcpio -p linux
fi

if pacman -Qi linux-zen &>/dev/null; then
    print_status "Regenerating initramfs for linux-zen kernel..."
    sudo mkinitcpio -p linux-zen
fi

# Enable Plymouth service
print_status "Enabling Plymouth services..."
sudo systemctl enable plymouth-start.service
sudo systemctl enable plymouth-quit.service
sudo systemctl enable plymouth-quit-wait.service

print_success "Plymouth configuration completed!"

echo
print_status "Summary of changes:"
echo "  ✓ Plymouth installed and configured"
echo "  ✓ Theme set to 'bgrt' (Arch logo)"
echo "  ✓ Boot entries updated with Plymouth options"
echo "  ✓ mkinitcpio.conf updated with Plymouth hook"
echo "  ✓ Initramfs regenerated"
echo "  ✓ Plymouth services enabled"

echo
print_status "Boot entries that were updated:"
for entry in $LINUX_ENTRIES $ZEN_ENTRIES; do
    entry_name=$(basename "$entry" .conf)
    echo "  - $entry_name"
done

echo
print_warning "Please reboot to see Plymouth in action!"
print_status "If you want to change the theme later, use: sudo plymouth-set-default-theme <theme-name>"
print_status "Available themes can be listed with: plymouth-list-themes"

echo
print_status "Backups created:"
echo "  - Boot entry backups: /boot/loader/entries/*.conf.backup"
echo "  - mkinitcpio backup: /etc/mkinitcpio.conf.backup"
