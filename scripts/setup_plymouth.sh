#!/bin/bash

# Plymouth Setup Script for Arch Linux with GRUB or systemd-boot
# This script configures Plymouth with the Arch Linux logo for both bootloaders

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

# Detect bootloader
detect_bootloader() {
    local bootloader=""

    # Check for systemd-boot
    if [[ -d /boot/loader && -f /boot/loader/loader.conf ]]; then
        bootloader="systemd-boot"
    # Check for GRUB
    elif [[ -f /boot/grub/grub.cfg ]] || [[ -f /boot/grub2/grub.cfg ]]; then
        bootloader="grub"
    # Check if GRUB is installed as package
    elif pacman -Qi grub &>/dev/null; then
        bootloader="grub"
    else
        print_error "Could not detect bootloader. This script supports GRUB and systemd-boot only."
        exit 1
    fi

    echo "$bootloader"
}

# Function to configure GRUB
configure_grub() {
    print_status "Configuring Plymouth for GRUB..."

    local grub_config="/etc/default/grub"

    if [[ ! -f "$grub_config" ]]; then
        print_error "GRUB configuration file not found at $grub_config"
        exit 1
    fi

    # Create backup
    sudo cp "$grub_config" "$grub_config.backup"

    # Check current GRUB_CMDLINE_LINUX_DEFAULT
    local current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config" | cut -d'"' -f2)

    # Add Plymouth parameters if not already present
    local new_cmdline="$current_cmdline"

    if [[ ! "$current_cmdline" =~ "splash" ]]; then
        new_cmdline="$new_cmdline splash"
    fi

    if [[ ! "$current_cmdline" =~ "plymouth" ]]; then
        new_cmdline="$new_cmdline plymouth.ignore-serial-consoles"
    fi

    # Clean up extra spaces
    new_cmdline=$(echo "$new_cmdline" | sed 's/  */ /g' | sed 's/^ *//;s/ *$//')

    # Update GRUB configuration
    sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"/" "$grub_config"

    print_success "Updated GRUB configuration"
    print_status "New kernel parameters: $new_cmdline"

    # Regenerate GRUB configuration
    print_status "Regenerating GRUB configuration..."
    if [[ -f /boot/grub/grub.cfg ]]; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    elif [[ -f /boot/grub2/grub.cfg ]]; then
        sudo grub-mkconfig -o /boot/grub2/grub.cfg
    else
        sudo grub-mkconfig -o /boot/grub/grub.cfg
    fi

    print_success "GRUB configuration regenerated"
}

# Function to configure systemd-boot
configure_systemdboot() {
    print_status "Configuring Plymouth for systemd-boot..."

    local boot_entries_dir="/boot/loader/entries"

    if [[ ! -d "$boot_entries_dir" ]]; then
        print_error "Boot entries directory not found at $boot_entries_dir"
        exit 1
    fi

    # Find kernel entries
    local linux_entries=$(find "$boot_entries_dir" -name "*.conf" -exec grep -l "linux.*vmlinuz-linux" {} \; 2>/dev/null)
    local zen_entries=$(find "$boot_entries_dir" -name "*.conf" -exec grep -l "linux.*vmlinuz-linux-zen" {} \; 2>/dev/null)

    print_status "Found boot entries:"
    echo
    if [[ -n "$linux_entries" ]]; then
        echo -e "${GREEN}Linux kernel entries:${NC}"
        for entry in $linux_entries; do
            local entry_name=$(basename "$entry" .conf)
            echo "  - $entry_name ($(basename "$entry"))"
        done
    fi

    if [[ -n "$zen_entries" ]]; then
        echo -e "${GREEN}Linux Zen kernel entries:${NC}"
        for entry in $zen_entries; do
            local entry_name=$(basename "$entry" .conf)
            echo "  - $entry_name ($(basename "$entry"))"
        done
    fi

    if [[ -z "$linux_entries" && -z "$zen_entries" ]]; then
        print_error "No Linux or Linux Zen kernel entries found!"
        exit 1
    fi

    echo

    # Function to update systemd-boot entry
    update_systemdboot_entry() {
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
    for entry in $linux_entries $zen_entries; do
        update_systemdboot_entry "$entry"
    done

    print_status "Boot entries that were updated:"
    for entry in $linux_entries $zen_entries; do
        local entry_name=$(basename "$entry" .conf)
        echo "  - $entry_name"
    done
}

print_status "Starting Plymouth configuration for Arch Linux..."

# Detect bootloader
BOOTLOADER=$(detect_bootloader)
print_success "Detected bootloader: $BOOTLOADER"

# Install Plymouth if not already installed
print_status "Checking Plymouth installation..."
if ! pacman -Qi plymouth &>/dev/null; then
    print_status "Installing Plymouth..."
    sudo pacman -S --needed plymouth
else
    print_success "Plymouth is already installed"
fi

# Set Plymouth theme to default Arch theme
print_status "Setting Plymouth theme to 'bgrt' (shows vendor logo - Arch on most systems)..."
sudo plymouth-set-default-theme bgrt

# Show available themes
print_status "Available Plymouth themes:"
plymouth-list-themes | while read theme; do
    echo "  - $theme"
done

# Configure bootloader-specific settings
case "$BOOTLOADER" in
    "grub")
        configure_grub
        ;;
    "systemd-boot")
        configure_systemdboot
        ;;
    *)
        print_error "Unsupported bootloader: $BOOTLOADER"
        exit 1
        ;;
esac

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

if pacman -Qi linux-lts &>/dev/null; then
    print_status "Regenerating initramfs for linux-lts kernel..."
    sudo mkinitcpio -p linux-lts
fi

if pacman -Qi linux-hardened &>/dev/null; then
    print_status "Regenerating initramfs for linux-hardened kernel..."
    sudo mkinitcpio -p linux-hardened
fi

# Enable Plymouth services
print_status "Enabling Plymouth services..."
sudo systemctl enable plymouth-start.service
sudo systemctl enable plymouth-quit.service
sudo systemctl enable plymouth-quit-wait.service

print_success "Plymouth configuration completed!"

echo
print_status "Summary of changes:"
echo "  ✓ Bootloader detected: $BOOTLOADER"
echo "  ✓ Plymouth installed and configured"
echo "  ✓ Theme set to 'bgrt' (Arch logo)"
case "$BOOTLOADER" in
    "grub")
        echo "  ✓ GRUB configuration updated with Plymouth options"
        echo "  ✓ GRUB config regenerated"
        ;;
    "systemd-boot")
        echo "  ✓ Boot entries updated with Plymouth options"
        ;;
esac
echo "  ✓ mkinitcpio.conf updated with Plymouth hook"
echo "  ✓ Initramfs regenerated for all installed kernels"
echo "  ✓ Plymouth services enabled"

echo
print_warning "Please reboot to see Plymouth in action!"
print_status "If you want to change the theme later, use: sudo plymouth-set-default-theme <theme-name>"
print_status "Available themes can be listed with: plymouth-list-themes"

echo
print_status "Backups created:"
case "$BOOTLOADER" in
    "grub")
        echo "  - GRUB config backup: /etc/default/grub.backup"
        ;;
    "systemd-boot")
        echo "  - Boot entry backups: /boot/loader/entries/*.conf.backup"
        ;;
esac
echo "  - mkinitcpio backup: /etc/mkinitcpio.conf.backup"
