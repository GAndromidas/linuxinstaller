#!/bin/bash
set -uo pipefail

# Gaming and performance tweaks installation for Arch Linux
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Gaming Mode Setup"

# Show Gaming Mode banner
figlet_banner "Gaming Mode"

# Check if user wants gaming mode (default to Yes)
echo -e "${CYAN}Would you like to enable Gaming Mode?${RESET}"
echo -e "${YELLOW}This includes: MangoHud, GameMode, Steam, Lutris, Wine, and more.${RESET}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
while true; do
    read -r -p "$(echo -e "${YELLOW}Enable Gaming Mode? [Y/n]: ${RESET}")" response
    response=${response,,}
    case "$response" in
        ""|y|yes)
            echo -e "\n"
            break
            ;;
        n|no)
            log_info "Gaming Mode skipped."
            echo -e "\n"
            return 0
            ;;
        *)
            echo -e "\n${RED}Please answer Y (yes) or N (no).${RESET}\n"
            ;;
    esac
done

# Install MangoHud for performance monitoring
step "Installing MangoHud"
MANGO_PACKAGES=("mangohud" "lib32-mangohud")
install_packages_quietly "${MANGO_PACKAGES[@]}"

# Install GameMode for performance optimization
step "Installing GameMode"
GAMEMODE_PACKAGES=("gamemode" "lib32-gamemode")
install_packages_quietly "${GAMEMODE_PACKAGES[@]}"

# Install additional gaming utilities
step "Installing gaming utilities"
GAMING_PACKAGES=(
    "steam"
    "lutris"
    "wine"
    "discord"
)
install_packages_quietly "${GAMING_PACKAGES[@]}"

# Install AUR gaming packages
step "Installing AUR gaming packages"
GAMING_AUR_PACKAGES=(
    "heroic-games-launcher-bin"
)
install_aur_quietly "${GAMING_AUR_PACKAGES[@]}"

# Install additional gaming-related Flatpaks
step "Installing gaming-related Flatpaks"
GAMING_FLATPAKS=(
    "com.vysp3r.ProtonPlus"
)
install_flatpak_quietly "${GAMING_FLATPAKS[@]}"

log_success "Gaming Mode setup completed." 