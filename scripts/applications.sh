#!/bin/bash
set -uo pipefail

# Simplified and Efficient Applications Installation
# Installs packages from programs.yaml in batches for speed and reliability.

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ARCHINSTALLER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$ARCHINSTALLER_ROOT/configs"

source "$SCRIPT_DIR/common.sh"

export SUDO_ASKPASS=   # Force sudo to prompt in terminal, not via GUI

# ===== YAML Parsing Functions =====

# Function to check if yq is available, install if not
ensure_yq() {
  if ! command -v yq &>/dev/null; then
    echo -e "${YELLOW}yq is required for YAML parsing. Installing...${RESET}"
    sudo pacman -S --noconfirm yq
    if ! command -v yq &>/dev/null; then
      log_error "Failed to install yq. Please install it manually: sudo pacman -S yq"
      return 1
    fi
  fi
  return 0
}

# Function to read packages from YAML
read_yaml_packages() {
  local yaml_file="$1"
  local yaml_path="$2"
  local -n packages_array="$3"
  packages_array=()
  local yq_output
  yq_output=$(yq -r "$yaml_path[].name" "$yaml_file" 2>/dev/null)
  if [[ $? -eq 0 && -n "$yq_output" ]]; then
    while IFS= read -r package; do
      [[ -z "$package" ]] && continue
      packages_array+=("$package")
    done <<< "$yq_output"
  fi
}

# Function to read simple package lists (without descriptions)
read_yaml_simple_packages() {
  local yaml_file="$1"
  local yaml_path="$2"
  local -n packages_array="$3"
  packages_array=()
  local yq_output
  yq_output=$(yq -r "$yaml_path[]" "$yaml_file" 2>/dev/null)
  if [[ $? -eq 0 && -n "$yq_output" ]]; then
    while IFS= read -r package; do
      [[ -z "$package" ]] && continue
      packages_array+=("$package")
    done <<< "$yq_output"
  fi
}

# --- Installation Functions ---

# Installs a list of packages using pacman
install_pacman_packages() {
    local packages_to_install=("$@")
    log_info "Installing ${#packages_to_install[@]} Pacman packages..."
    if ! sudo pacman -S --noconfirm --needed "${packages_to_install[@]}"; then
        log_error "Failed to install some Pacman packages."
    else
        log_success "All Pacman packages installed successfully."
    fi
}

# Installs a list of AUR packages using paru
install_aur_packages() {
    local packages_to_install=("$@")
    log_info "Installing ${#packages_to_install[@]} AUR packages..."
    if ! paru -S --noconfirm --needed "${packages_to_install[@]}"; then
        log_error "Failed to install some AUR packages."
    else
        log_success "All AUR packages installed successfully."
    fi
}

# Installs a list of Flatpak applications
install_flatpak_packages() {
    local packages_to_install=("$@")
    log_info "Installing ${#packages_to_install[@]} Flatpak applications..."
        if ! flatpak install -y "${packages_to_install[@]}"; then
        log_error "Failed to install some Flatpak applications."
    else
        log_success "All Flatpak applications installed successfully."
    fi
}

# Dummy functions to avoid errors if they are not defined in common.sh
check_paru() {
    command -v paru &>/dev/null
}

check_flatpak() {
    command -v flatpak &>/dev/null
}

print_applications_summary() {
    # This is a placeholder. You might want to implement a summary function.
    log_info "Application installation summary:"
    log_info "Installed Pacman packages: ${#pacman_packages[@]}"
    log_info "Installed AUR packages: ${#aur_packages[@]}"
    log_info "Installed Flatpak packages: ${#flatpak_packages[@]}"
}
# ===== Main Logic =====

# Check if programs.yaml exists
PROGRAMS_YAML="$CONFIGS_DIR/programs.yaml"
if [[ ! -f "$PROGRAMS_YAML" ]]; then
  log_error "Programs configuration file not found: $PROGRAMS_YAML"
  return 1
fi

# Ensure yq is available
if ! ensure_yq; then
  return 1
fi

# Determine installation mode
if [[ -z "${INSTALL_MODE-}" ]]; then
    log_error "INSTALL_MODE is not set. Please run the installer from the main menu."
    return 1
fi

log_info "Starting application installation in '$INSTALL_MODE' mode."

# --- Gather all packages to be installed ---

pacman_packages=()
aur_packages=()
flatpak_packages=()
remove_packages=()

# Pacman packages
read_yaml_packages "$PROGRAMS_YAML" ".pacman.packages" pacman_base
pacman_packages+=("${pacman_base[@]}")

# Essential packages
read_yaml_packages "$PROGRAMS_YAML" ".essential.$INSTALL_MODE" essential_mode
pacman_packages+=("${essential_mode[@]}")

# AUR packages
read_yaml_packages "$PROGRAMS_YAML" ".aur.$INSTALL_MODE" aur_mode
aur_packages+=("${aur_mode[@]}")

# Desktop environment specific packages
de_lower=""
case "$XDG_CURRENT_DESKTOP" in
  KDE) de_lower="kde" ;;
  GNOME) de_lower="gnome" ;;
  COSMIC) de_lower="cosmic" ;;
  *) de_lower="generic" ;;
esac

if [[ "$de_lower" != "generic" ]]; then
    read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.$de_lower.install" de_install
    pacman_packages+=("${de_install[@]}")

    read_yaml_simple_packages "$PROGRAMS_YAML" ".desktop_environments.$de_lower.remove" de_remove
    remove_packages+=("${de_remove[@]}")
fi

# Flatpak packages
read_yaml_packages "$PROGRAMS_YAML" ".flatpak.$de_lower.$INSTALL_MODE" flatpak_mode
flatpak_packages+=("${flatpak_mode[@]}")


# --- Installation Process ---

# 1. Remove unwanted packages
if [ ${#remove_packages[@]} -gt 0 ]; then
    step "Removing conflicting or unnecessary packages..."
    # Filter out packages that are not installed
    packages_to_remove=()
    for pkg in "${remove_packages[@]}"; do
        if pacman -Q "$pkg" &>/dev/null; then
            packages_to_remove+=("$pkg")
        fi
    done

    if [ ${#packages_to_remove[@]} -gt 0 ]; then
        log_info "Removing: ${packages_to_remove[*]}"
        sudo pacman -Rns --noconfirm "${packages_to_remove[@]}"
    else
        log_success "No packages to remove."
    fi
else
    log_success "No packages slated for removal."
fi

# 2. Install Pacman packages
if [ ${#pacman_packages[@]} -gt 0 ]; then
    step "Installing Pacman packages..."
    install_pacman_packages "${pacman_packages[@]}"
else
    log_success "No Pacman packages to install."
fi

# 3. Install AUR packages
if [ ${#aur_packages[@]} -gt 0 ]; then
    step "Installing AUR packages..."
    if check_paru; then
        install_aur_packages "${aur_packages[@]}"
    else
        log_warning "paru (AUR helper) is not installed. Skipping AUR packages."
    fi
else
    log_success "No AUR packages to install."
fi

# 4. Install Flatpak packages
if [ ${#flatpak_packages[@]} -gt 0 ]; then
    step "Installing Flatpak applications..."
    if check_flatpak; then
        install_flatpak_packages "${flatpak_packages[@]}"
    else
        log_warning "flatpak is not installed. Skipping Flatpak applications."
    fi
else
    log_success "No Flatpak applications to install."
fi


# --- Final Summary ---
print_applications_summary
log_success "Application installation process completed."
return 0