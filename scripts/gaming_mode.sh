#!/bin/bash
set -uo pipefail

# Gaming and performance tweaks installation for Arch Linux
# Get the directory where this script is located, resolving symlinks
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$ARCHINSTALLER_ROOT/configs"

source "$SCRIPT_DIR/common.sh"
source "$ARCHINSTALLER_ROOT/scripts/cachyos_support.sh"

# Initialize CachyOS detection
detect_cachyos >/dev/null 2>&1 || true

step "Gaming Mode Setup"

if $IS_CACHYOS; then
  log_info "CachyOS detected - gaming packages will be installed using CachyOS compatibility mode"
fi

# Show Gaming Mode banner
figlet_banner "Gaming Mode"

# Check if user wants gaming mode (default to Yes)
if command -v gum >/dev/null 2>&1; then
    gum style --foreground 51 "Would you like to enable Gaming Mode?"
    gum style --foreground 226 "This includes: Discord, GameMode, Heroic Games Launcher, Lutris, MangoHud, OBS Studio, ProtonPlus, Steam, and Wine."

    if ! gum confirm --default=true "Enable Gaming Mode?"; then
        gum style --foreground 51 "Gaming Mode skipped."
        return 0
    fi
else
    # Fallback to traditional prompts
    echo -e "${CYAN}Would you like to enable Gaming Mode?${RESET}"
    echo -e "${YELLOW}This includes: Discord, GameMode, Heroic Games Launcher, Lutris, MangoHud, OBS Studio, ProtonPlus, Steam, and Wine.${RESET}"
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
fi

# Install MangoHud for performance monitoring
step "Installing MangoHud"
MANGO_PACKAGES=("mangohud" "lib32-mangohud")
install_packages_quietly "${MANGO_PACKAGES[@]}"

# Copy MangoHud configuration
step "Configuring MangoHud"
MANGOHUD_CONFIG_DIR="$HOME/.config/MangoHud"
MANGOHUD_CONFIG_SOURCE="$CONFIGS_DIR/MangoHud.conf"

# Create MangoHud config directory if it doesn't exist
mkdir -p "$MANGOHUD_CONFIG_DIR"

# Copy MangoHud configuration file, replacing if it exists
if [ -f "$MANGOHUD_CONFIG_SOURCE" ]; then
    cp "$MANGOHUD_CONFIG_SOURCE" "$MANGOHUD_CONFIG_DIR/MangoHud.conf"
    log_success "MangoHud configuration copied successfully."
else
    log_warning "MangoHud configuration file not found at $MANGOHUD_CONFIG_SOURCE"
fi

# Install GameMode for performance optimization
step "Installing GameMode"
GAMEMODE_PACKAGES=("gamemode" "lib32-gamemode")
install_packages_quietly "${GAMEMODE_PACKAGES[@]}"

# Install additional gaming utilities
step "Installing gaming utilities"
GAMING_PACKAGES=(
    "discord"
    "lutris"
    "obs-studio"
    "steam"
    "wine"
)
install_packages_quietly "${GAMING_PACKAGES[@]}"

# Install AUR gaming packages
step "Installing AUR gaming packages"
GAMING_AUR_PACKAGES=(
    "heroic-games-launcher-bin"
)

# Install AUR packages using yay
if command -v yay &>/dev/null; then
  total=${#GAMING_AUR_PACKAGES[@]}
  current=0
  failed_packages=()

  for pkg in "${GAMING_AUR_PACKAGES[@]}"; do
    ((current++))
    print_progress "$current" "$total" "$pkg"
    if pacman -Q "$pkg" &>/dev/null; then
      print_status " [SKIP] Already installed" "$YELLOW"
    else
      if yay -S --noconfirm --needed "$pkg" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        INSTALLED_PACKAGES+=("$pkg (AUR)")
      else
        print_status " [FAIL]" "$RED"
        failed_packages+=("$pkg")
      fi
    fi
  done

  if [ ${#failed_packages[@]} -gt 0 ]; then
    log_warning "Some AUR gaming packages failed to install: ${failed_packages[*]}"
  fi
else
  log_error "yay not found. Skipping AUR gaming packages."
fi

# Install additional gaming-related Flatpaks
step "Installing gaming-related Flatpaks"
GAMING_FLATPAKS=(
    "com.vysp3r.ProtonPlus"
)

if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak remote-list | grep -q flathub; then
    log_warning "Flathub repository not enabled. Adding Flathub..."
    sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi

  total=${#GAMING_FLATPAKS[@]}
  current=0
  failed_packages=()

  for pkg in "${GAMING_FLATPAKS[@]}"; do
    ((current++))
    print_progress "$current" "$total" "$pkg"
    if flatpak list | grep -q "$pkg"; then
      print_status " [SKIP] Already installed" "$YELLOW"
    else
      if sudo flatpak install -y flathub "$pkg" >/dev/null 2>&1; then
        print_status " [OK]" "$GREEN"
        INSTALLED_PACKAGES+=("$pkg (Flatpak)")
      else
        print_status " [FAIL]" "$RED"
        failed_packages+=("$pkg")
      fi
    fi
  done

  if [ ${#failed_packages[@]} -gt 0 ]; then
    log_warning "Some Flatpak gaming packages failed to install: ${failed_packages[*]}"
  fi
else
  log_error "Flatpak not installed. Skipping Flatpak gaming packages."
fi

if $IS_CACHYOS; then
  log_success "Gaming Mode setup completed with CachyOS compatibility."
else
  log_success "Gaming Mode setup completed."
fi
