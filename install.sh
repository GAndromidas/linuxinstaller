#!/bin/bash
set -uo pipefail

# Check if running as root, re-exec with sudo if not
if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# =============================================================================
# LinuxInstaller - Unified Post-Installation Script
# Supports: Arch Linux, Fedora, Debian, Ubuntu
# =============================================================================

# Show LinuxInstaller ASCII art banner
show_linuxinstaller_ascii() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
     _     _                  ___           _        _ _
    | |   (_)_ __  _   ___  _|_ _|_ __  ___| |_ __ _| | | ___ _ __
    | |   | | '_ \| | | \ \/ /| || '_ \/ __| __/ _` | | |/ _ \ '__|
    | |___| | | | | |_| |>  < | || | | \__ \ || (_| | | |  __/ |
    |_____|_|_| |_|\__,_/_/\_\___|_| |_|___/\__\__,_|_|_|\___|_|
EOF
    echo -e "${RESET}"
}

# Enhanced Menu Function
show_menu() {
    show_linuxinstaller_ascii

    if ! supports_gum; then
        echo "Note: gum not detected, using text menu"
    fi

    echo ""

    # If gum is available and we have an interactive TTY, try gum-based UI
    if supports_gum && [ -t 0 ]; then
        local choice
        choice=$(gum choose \
            "Standard - Complete setup with all recommended packages" \
            "Minimal - Essential tools only for lightweight installations" \
            "Server - Headless server configuration" \
            "Exit" \
            --cursor.foreground "$GUM_PRIMARY_FG" --cursor "→" \
            --selected.foreground "$GUM_PRIMARY_FG")

        case "$choice" in
            "Standard - Complete setup with all recommended packages")
                export INSTALL_MODE="standard" ;;
            "Minimal - Essential tools only for lightweight installations")
                export INSTALL_MODE="minimal" ;;
            "Server - Headless server configuration")
                export INSTALL_MODE="server" ;;
            "Exit")
                echo "Exiting..." ; exit 0 ;;
        esac

        echo ""
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "You selected: $choice"
        echo ""

        if [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; then
            if gum confirm "Install Gaming Package Suite?" --default=true; then
                export INSTALL_GAMING=true
            else
                export INSTALL_GAMING=false
            fi
        else
            export INSTALL_GAMING=false
        fi
        return
    fi

    # Fallback plain-text menu
    local text_choice
    while true; do
        echo "Please select an installation mode:"
        echo "  1) Standard - Complete setup with all recommended packages"
        echo "  2) Minimal - Essential tools only for lightweight installations"
        echo "  3) Server - Headless server configuration"
        echo "  4) Exit"
        read -r -t 300 -p "Enter choice [1-4]: " text_choice 2>/dev/null || {
            echo "No input received. Using default: Standard"
            text_choice="1"
            break
        }

        case "$text_choice" in
            1) export INSTALL_MODE="standard" ; break ;;
            2) export INSTALL_MODE="minimal" ; break ;;
            3) export INSTALL_MODE="server" ; break ;;
            4) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice, please try again." ;;
        esac
    done

    echo ""

    local friendly
    case "$INSTALL_MODE" in
        standard) friendly="Standard - Complete setup with all recommended packages" ;;
        minimal)  friendly="Minimal - Essential tools only for lightweight installations" ;;
        server)   friendly="Server - Headless server configuration" ;;
        *)        friendly="$INSTALL_MODE" ;;
    esac

    echo "You selected: $friendly"

    if { [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; } && [ -z "${CUSTOM_GROUPS:-}" ]; then
        if [ -t 0 ]; then
            read -r -p "Install Gaming Package Suite? [Y/n]: " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
                export INSTALL_GAMING=true
            else
                export INSTALL_GAMING=false
            fi
        else
            export INSTALL_GAMING=false
        fi
    else
        if [[ "${CUSTOM_GROUPS:-}" == *"Gaming"* ]]; then
            export INSTALL_GAMING=true
        fi
    fi

    echo ""
}

# Color variables
CYAN='\033[0;36m'
BLUE='\033[0;34m'
RESET='\033[0m'

# --- Configuration & Paths ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# --- Source Helpers ---
# We need distro detection and common utilities immediately
if [ -f "$SCRIPTS_DIR/common.sh" ]; then
  source "$SCRIPTS_DIR/common.sh"
else
  echo "FATAL: common.sh not found in $SCRIPTS_DIR. Cannot continue."
  exit 1
fi

if [ -f "$SCRIPTS_DIR/distro_check.sh" ]; then
  source "$SCRIPTS_DIR/distro_check.sh"
else
  echo "FATAL: distro_check.sh not found in $SCRIPTS_DIR. Cannot continue."
  exit 1
fi

# Optional Wake-on-LAN integration (sourced if present).
# The module integrates the wakeonlan helper so LinuxInstaller can auto-configure WoL.
if [ -f "$SCRIPTS_DIR/wakeonlan_config.sh" ]; then
  source "$SCRIPTS_DIR/wakeonlan_config.sh"
fi

# Optional power management helper (detection + configuration).
# This module provides `detect_system_info`, `show_system_info`, and
# `configure_power_management` to auto-detect CPU/GPU/RAM and configure
# power-profiles-daemon / cpupower / tuned as appropriate.
if [ -f "$SCRIPTS_DIR/power_config.sh" ]; then
  source "$SCRIPTS_DIR/power_config.sh"
fi

# --- Global Variables ---
# Flags
VERBOSE=false
DRY_RUN=false
TOTAL_STEPS=0
CURRENT_STEP=0
INSTALL_MODE="standard"

# Track installed helper (gum) to clean up later
GUM_INSTALLED_BY_SCRIPT=false

# --- Helper Functions ---

# Display help message and usage information
show_help() {
  cat << EOF
LinuxInstaller - Unified Post-Install Script

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -v, --verbose   Show detailed output
    -d, --dry-run   Simulate installation (no changes made)

 DESCRIPTION:
     A smart, cross-distribution installer that configures your system,
     installs packages, and applies tweaks.
     Supports Arch, Fedora, Debian, and Ubuntu.

 INSTALLATION MODES:
     Standard        Complete setup with all recommended packages
     Minimal         Essential tools only for lightweight installations
     Server          Headless server configuration

 EXAMPLES:
     ./install.sh                Run with interactive prompts
     ./install.sh --verbose      Run with detailed output
     ./install.sh --dry-run      Preview changes without applying them

EOF
  exit 0
}

# Bootstrap essential tools (gum UI helper) for the installer
bootstrap_tools() {
    log_info "Bootstrapping installer tools..."

    # Try to proceed even when network is flaky, but warn if no internet
    if ! ping -c 1 -W 5 google.com >/dev/null 2>&1; then
        log_warn "No internet connection detected. Some helper installs may fail or be skipped."
    fi

    # 1. GUM (UI) - try package manager, then fallback to binary download
    if ! supports_gum; then
        if [ "$DRY_RUN" = true ]; then
            return
        fi

        # Try package manager first
        if [ "$DISTRO_ID" == "arch" ]; then
            if pacman -S --noconfirm gum >/dev/null 2>&1; then
                GUM_INSTALLED_BY_SCRIPT=true
                supports_gum >/dev/null 2>&1 || true
            fi
        else
            if install_pkg gum >/dev/null 2>&1; then
                GUM_INSTALLED_BY_SCRIPT=true
                supports_gum >/dev/null 2>&1 || true
            fi
        fi
    fi
}




# Install a group of packages based on mode and package type (native, aur, flatpak, snap)
install_package_group() {
    local section_path="$1"
    local title="$2"
    local pkg_type="${3:-}"  # Optional: install only specific package type

    log_info "Processing package group: $title ($section_path)"

    # If specific package type requested, only process that type
    local pkg_types
    if [ -n "$pkg_type" ]; then
        pkg_types="$pkg_type"
    else
        # Determine package types available for this distro
        case "$DISTRO_ID" in
            arch)   pkg_types="native aur flatpak" ;;
            ubuntu) pkg_types="native snap flatpak" ;;
            *)      pkg_types="native flatpak" ;; # fedora, debian
        esac
    fi

    for type in $pkg_types; do
        # Try distro-provided package function first (preferred)
        local packages=()
        if declare -f distro_get_packages >/dev/null 2>&1; then
            # distro_get_packages should print one package per line; capture and normalize
            mapfile -t tmp < <(distro_get_packages "$section_path" "$type" 2>/dev/null || true)
            mapfile -t packages < <(printf "%s\n" "${tmp[@]}" | sed '/^[[:space:]]*null[[:space:]]*$/d' | sed '/^[[:space:]]*$/d')
        else
            # YAML-driven discovery has been removed.
            # Package lists must be provided by the distro module via 'distro_get_packages()'.
            continue
        fi

        if [ ${#packages[@]} -eq 0 ]; then
            continue
        fi

        # Deduplicate package list while preserving order to avoid redundant installs
        if [ ${#packages[@]} -gt 1 ]; then
            declare -A _li_seen_pkgs
            local _li_deduped=()
            for pkg in "${packages[@]}"; do
                if [ -n "$pkg" ] && [ -z "${_li_seen_pkgs[$pkg]:-}" ]; then
                    _li_deduped+=("$pkg")
                    _li_seen_pkgs[$pkg]=1
                fi
            done
            # Replace packages with deduplicated list
            packages=("${_li_deduped[@]}")
            unset _li_seen_pkgs
        fi

        if [ "$DRY_RUN" = true ]; then
            continue
        fi

        # Installation command selection
        local install_cmd=""
        case "$type" in
            native)
                if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
                    install_cmd="DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM"
                else
                    install_cmd="$PKG_INSTALL $PKG_NOCONFIRM"
                fi
                ;;
            aur)
                if command -v yay >/dev/null 2>&1; then
                    install_cmd="yay -S --noconfirm"
                elif command -v paru >/dev/null 2>&1; then
                    install_cmd="paru -S --noconfirm"
                else
                    continue
                fi
                ;;
            flatpak)
                if ! command -v flatpak >/dev/null 2>&1; then
                    if [ "$DISTRO_ID" = "debian" ] || [ "$DISTRO_ID" = "ubuntu" ]; then
                        DEBIAN_FRONTEND=noninteractive $PKG_INSTALL $PKG_NOCONFIRM flatpak >/dev/null 2>&1 || true
                    else
                        $PKG_INSTALL $PKG_NOCONFIRM flatpak >/dev/null 2>&1 || true
                    fi
                fi
                install_cmd="flatpak install flathub -y"
                ;;
            snap)
                install_cmd="snap install"
                ;;
        esac

    # Enable password asterisks for sudo prompts (visible feedback when typing)
    enable_password_feedback() {
        local sudoers_file="/etc/sudoers"

        if [ -f "$sudoers_file" ]; then
            if ! grep -q "Defaults pwfeedback" "$sudoers_file"; then
                log_info "Enabling password asterisks for sudo prompts..."
                case "$DISTRO_ID" in
                    arch)
                        visudo -c "Defaults pwfeedback" >/dev/null 2>&1
                        if [ $? -eq 0 ]; then
                            log_success "Password asterisks enabled via visudo (Arch)"
                        else
                            log_warn "Failed to enable password asterisks via visudo"
                        fi
                        ;;
                    debian|ubuntu)
                        if command -v visudo >/dev/null 2>&1; then
                            visudo -c "Defaults pwfeedback" >/dev/null 2>&1
                            if [ $? -eq 0 ]; then
                                log_success "Password asterisks enabled via visudo ($DISTRO_ID)"
                            else
                                log_warn "Failed to enable password asterisks via visudo"
                            fi
                        else
                            echo "Defaults pwfeedback" >> "$sudoers_file"
                            log_success "Password asterisks enabled via direct echo ($DISTRO_ID)"
                        fi
                        ;;
                    fedora)
                        if command -v visudo >/dev/null 2>&1; then
                            visudo -c "Defaults pwfeedback" >/dev/null 2>&1
                            if [ $? -eq 0 ]; then
                                log_success "Password asterisks enabled via visudo (Fedora)"
                            else
                                log_warn "Failed to enable password asterisks via visudo"
                            fi
                        else
                            echo "Defaults pwfeedback" >> "$sudoers_file"
                            log_success "Password asterisks enabled via direct echo (Fedora)"
                        fi
                        ;;
                    *)
                        if command -v visudo >/dev/null 2>&1; then
                            visudo -c "Defaults pwfeedback" >/dev/null 2>&1
                            if [ $? -eq 0 ]; then
                                log_success "Password asterisks enabled via visudo"
                            else
                                log_warn "Failed to enable password asterisks via visudo"
                            fi
                        else
                            echo "Defaults pwfeedback" >> "$sudoers_file"
                            log_success "Password asterisks enabled via direct echo"
                            log_warn "Please run 'visudo' to validate sudoers file"
                        fi
                        ;;
                esac
            else
                log_info "Password feedback already enabled"
            fi
        else
            log_warn "sudoers file not found, skipping password feedback configuration"
        fi
    }

        # Track installed packages
        local installed=()
        local skipped=()
        local failed=()

        # Execute installation with gum spin
        if [ "$type" = "flatpak" ]; then
            for pkg in "${packages[@]}"; do
                pkg="$(echo "$pkg" | xargs)"
                
                # Check if flatpak is already installed
                if flatpak list 2>/dev/null | grep -q "^${pkg}\s"; then
                    skipped+=("$pkg")
                    continue
                fi

                # Check if package exists (remote check)
                # Use flatpak search instead of info to check if package is available
                # Note: This check is optional, flatpak install will fail if package doesn't exist
                # Commented out to be less strict and let installation proceed
                # if ! flatpak search "$pkg" 2>/dev/null | grep -q "$pkg"; then
                #     log_warn "Flatpak package '$pkg' might not exist, attempting installation"
                # fi

                if supports_gum; then
                    if gum spin --spinner dot --title "" -- $install_cmd "$pkg" >/dev/null 2>&1; then
                        installed+=("$pkg")
                    else
                        failed+=("$pkg")
                    fi
                else
                    if $install_cmd "$pkg" >/dev/null 2>&1; then
                        installed+=("$pkg")
                    else
                        failed+=("$pkg")
                    fi
                fi
            done
        else
            for pkg in "${packages[@]}"; do
                pkg="$(echo "$pkg" | xargs)"

                # Resolve package name for current distro
                local resolved_pkg
                resolved_pkg="$(resolve_package_name "$pkg")"

                # If resolved_pkg is empty, skip this package (removed for this distro)
                if [ -z "$resolved_pkg" ]; then
                    continue
                fi

                # For native packages, check if all resolved packages are installed
                if [ "$type" = "native" ]; then
                    local all_installed=true
                    local check_pkg
                    for check_pkg in $resolved_pkg; do
                        if ! is_package_installed "$check_pkg"; then
                            all_installed=false
                            break
                        fi
                    done

                    if [ "$all_installed" = true ]; then
                        skipped+=("$pkg")
                        continue
                    fi

                    # Check if packages exist in repositories
                    local missing_in_repo=false
                    for check_pkg in $resolved_pkg; do
                        if ! package_exists "$check_pkg"; then
                            missing_in_repo=true
                            break
                        fi
                    done

                    if [ "$missing_in_repo" = true ]; then
                        log_warn "Package '$pkg' (resolved to: $resolved_pkg) not found in repositories, attempting installation anyway"
                    fi
                fi

                # Install all resolved packages
                if supports_gum; then
                    if gum spin --spinner dot --title "" -- $install_cmd $resolved_pkg >/dev/null 2>&1; then
                        installed+=("$pkg")
                    else
                        failed+=("$pkg")
                    fi
                else
                    if $install_cmd $resolved_pkg >/dev/null 2>&1; then
                        installed+=("$pkg")
                    else
                        failed+=("$pkg")
                    fi
                fi
            done
        fi

        # Show summary only
        if [ ${#installed[@]} -gt 0 ] || [ ${#failed[@]} -gt 0 ]; then
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "$title ($type)"
            else
                echo -e "\n${WHITE}$title ($type)${RESET}"
            fi
            
            if [ ${#installed[@]} -gt 0 ]; then
                if supports_gum; then
                    gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ ${installed[*]}"
                else
                    echo -e "${GREEN}✓ ${installed[*]}${RESET}"
                fi
            fi
            
            if [ ${#failed[@]} -gt 0 ]; then
                if supports_gum; then
                    gum style --margin "0 4" --foreground "$GUM_ERROR_FG" "✗ Failed: ${failed[*]}"
                else
                    echo -e "${RED}✗ Failed: ${failed[*]}${RESET}"
                fi
            fi
        fi
    done
}

# --- User Shell & Config Setup ---

# Configure zsh shell and user config files (zshrc, starship, fastfetch)
configure_user_shell_and_configs() {
    step "Configuring Zsh and user-level configs (zsh, starship, fastfetch)"
    local target_user="${SUDO_USER:-$USER}"
    local home_dir
    home_dir="$(eval echo ~${target_user})"
    local cfg_dir="$CONFIGS_DIR/$DISTRO_ID"

    local zsh_packages=(zsh zsh-autosuggestions zsh-syntax-highlighting starship fastfetch)
    local installed=()
    local skipped=()
    local failed=()

    for pkg in "${zsh_packages[@]}"; do
        if is_package_installed "$pkg"; then
            skipped+=("$pkg")
            continue
        fi

        if ! package_exists "$pkg"; then
            failed+=("$pkg")
            continue
        fi

        if supports_gum; then
            if gum spin --spinner dot --title "" -- install_pkg "$pkg" >/dev/null 2>&1; then
                installed+=("$pkg")
            else
                failed+=("$pkg")
            fi
        else
            if install_pkg "$pkg" >/dev/null 2>&1; then
                installed+=("$pkg")
            else
                failed+=("$pkg")
            fi
        fi
    done

    # Deploy .zshrc
    if [ -f "$cfg_dir/.zshrc" ]; then
        cp -a "$cfg_dir/.zshrc" "$home_dir/.zshrc" || true
        chown "$target_user:$target_user" "$home_dir/.zshrc" || true
    fi

    # Deploy starship config
    if [ -f "$cfg_dir/starship.toml" ]; then
        mkdir -p "$home_dir/.config"
        cp -a "$cfg_dir/starship.toml" "$home_dir/.config/starship.toml" || true
        chown "$target_user:$target_user" "$home_dir/.config/starship.toml" || true
    fi

    # Deploy fastfetch config
    if [ -f "$cfg_dir/config.jsonc" ]; then
        mkdir -p "$home_dir/.config/fastfetch"
        cp -a "$cfg_dir/config.jsonc" "$home_dir/.config/fastfetch/config.jsonc" || true
        chown -R "$target_user:$target_user" "$home_dir/.config/fastfetch" || true
    fi

    return 0
}

# --- Final Cleanup ---

# Clean up temporary helper packages (gum) installed by the script
final_cleanup() {
    step "Final cleanup and optional helper removal"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Final cleanup skipped."
        return
    fi

    local remove_list=()
    [ "${GUM_INSTALLED_BY_SCRIPT:-false}" = true ] && remove_list+=("gum")

    if [ ${#remove_list[@]} -eq 0 ]; then
        log_info "No temporary helper packages were installed by the script."
        return
    fi

    # Prompt the user whether to remove them (interactive)
    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "Temporary helper packages detected:"
        gum style --margin "0 4" --foreground "$GUM_BODY_FG" "${remove_list[*]}"
            if gum confirm --default=false "Remove these helper packages now?"; then
            for pkg in "${remove_list[@]}"; do
                log_info "Removing $pkg..."
                if remove_pkg "$pkg"; then
                    log_success "Removed $pkg via package manager"
                else
                    # Fallback: try removing binary placed under /usr/local/bin
                    if [ -f "/usr/local/bin/$pkg" ]; then
                        rm -f "/usr/local/bin/$pkg" && log_success "Removed /usr/local/bin/$pkg" || log_warn "Failed to remove /usr/local/bin/$pkg"
                    else
                        log_warn "Failed to remove $pkg via package manager"
                    fi
                fi
            done
        else
            log_info "Keeping helper packages as requested by the user."
        fi
    else
        echo "Temporary helper packages detected: ${remove_list[*]}"
        read -r -p "Remove these helper packages now? [y/N]: " resp
        if [[ "$resp" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            for pkg in "${remove_list[@]}"; do
                log_info "Removing $pkg..."
                if remove_pkg "$pkg"; then
                    log_success "Removed $pkg via package manager"
                else
                    if [ -f "/usr/local/bin/$pkg" ]; then
                        rm -f "/usr/local/bin/$pkg" && log_success "Removed /usr/local/bin/$pkg" || log_warn "Failed to remove /usr/local/bin/$pkg"
                    else
                        log_warn "Failed to remove $pkg via package manager"
                    fi
                fi
            done
        fi
    fi
}
# --- Main Execution Flow ---

# 1. Parse Arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) show_help ;;
    -v|--verbose) VERBOSE=true ;;
    -d|--dry-run) DRY_RUN=true ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# 2. Environment Setup
# We must detect distro first to know how to install prerequisites
detect_distro # Sets DISTRO_ID, PKG_INSTALL, etc.
detect_de # Sets XDG_CURRENT_DESKTOP (e.g., KDE, GNOME)

# Source distro module early so it can provide package lists via `distro_get_packages()`
case "$DISTRO_ID" in
    "arch")
        if [ -f "$SCRIPTS_DIR/arch_config.sh" ]; then
            source "$SCRIPTS_DIR/arch_config.sh"
        fi
        ;;
    "fedora")
        if [ -f "$SCRIPTS_DIR/fedora_config.sh" ]; then
            source "$SCRIPTS_DIR/fedora_config.sh"
        fi
        ;;
    "debian"|"ubuntu")
        if [ -f "$SCRIPTS_DIR/debian_config.sh" ]; then
            source "$SCRIPTS_DIR/debian_config.sh"
        fi
        ;;
esac

# programs.yaml fallback removed; package lists are provided by distro modules (via distro_get_packages())

# Bootstrap UI tools
bootstrap_tools

# 3. Mode Selection
# Ensure that user is always prompted in interactive runs (so that menu appears on ./install.sh).
# For non-interactive runs (CI, scripts), preserve existing behavior by selecting a sensible default.
clear
if [ -t 0 ]; then
    # Interactive terminal - show menu
    if [ "$DRY_RUN" = false ]; then
        show_menu
    else
        log_warn "Dry-Run Mode Active: No changes will be applied."
    fi
else
    # Non-interactive: only set a default mode if none exists to avoid prompting
    if [ -z "${INSTALL_MODE:-}" ]; then
        export INSTALL_MODE="${INSTALL_MODE:-standard}"
        log_info "Non-interactive: defaulting to install mode: $INSTALL_MODE"
    fi
fi

# 4. Core Execution Loop
# We define a list of logical steps.

# Step: System Update
step "Updating System Repositories"
if [ "$DRY_RUN" = false ]; then
    update_system
fi

# Step: Run Distro System Preparation (install essentials, etc.)
# Run distro-specific system preparation early so essential helpers are present
# before package installation and mark the step complete to avoid duplication.
# Note: For Arch, this includes pacman configuration via configure_pacman_arch
DSTR_PREP_FUNC="${DISTRO_ID}_system_preparation"
DSTR_PREP_STEP="${DSTR_PREP_FUNC}"
if declare -f "$DSTR_PREP_FUNC" >/dev/null 2>&1; then
    step "Running system preparation for $DISTRO_ID"
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run $DSTR_PREP_FUNC"
    else
        if ! "$DSTR_PREP_FUNC"; then
            log_warn "$DSTR_PREP_FUNC reported issues"
        fi
    fi
fi

# Step: Install Packages based on Mode
step "Installing Packages ($INSTALL_MODE)"

# Install Base packages (native only) - Standard/Minimal/Server
install_package_group "$INSTALL_MODE" "Base System" "native"

# Install distro-provided 'essential' group (native only)
install_package_group "essential" "Essential Packages" "native"

# Install Desktop Environment Specific Packages (native only)
if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "$INSTALL_MODE" != "server" ]]; then
    DE_KEY=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
    if [[ "$DE_KEY" == *"kde"* ]]; then DE_KEY="kde"; fi
    if [[ "$DE_KEY" == *"gnome"* ]]; then DE_KEY="gnome"; fi

    step "Installing Desktop Environment Packages ($DE_KEY)"
    install_package_group "$DE_KEY" "$XDG_CURRENT_DESKTOP Environment" "native"
fi

# Install AUR packages for Arch Linux
if [ "$DISTRO_ID" == "arch" ]; then
    install_package_group "$INSTALL_MODE" "AUR Packages" "aur"
fi

# Install COPR/eza package for Fedora
if [ "$DISTRO_ID" == "fedora" ]; then
    step "Installing COPR/eza Package"
    if [ "$DRY_RUN" = false ]; then
        if command -v dnf >/dev/null; then
            # Install eza from COPR
            if dnf copr enable -y eza-community/eza >/dev/null 2>&1; then
                install_pkg eza
                log_success "Enabled eza COPR repository and installed eza"
            else
                log_warn "Failed to enable eza COPR repository"
            fi
        else
            log_warn "dnf not found, skipping eza installation"
        fi
    fi
fi

# Install Flatpak packages for all sections (Base, Desktop, Gaming)
install_package_group "$INSTALL_MODE" "Flatpak Packages" "flatpak"

if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "$INSTALL_MODE" != "server" ]]; then
    install_package_group "$DE_KEY" "Flatpak Packages" "flatpak"
fi

# Handle Custom Addons if any (rudimentary handling)
if [[ "${CUSTOM_GROUPS:-}" == *"Gaming"* ]]; then
    install_package_group "gaming" "Gaming Suite" "native"
    install_package_group "gaming" "Gaming Suite" "flatpak"
fi

# Use to gaming decision made at menu time (if applicable)
if { [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; } && [ -z "${CUSTOM_GROUPS:-}" ]; then
    if [ "${INSTALL_GAMING:-false}" = "true" ]; then
        # Gaming packages already installed above (native and flatpak)
        log_info "Gaming packages already installed in previous steps"
    fi
fi

# ------------------------------------------------------------------
# Wake-on-LAN auto-configuration step
#
# If wakeonlan integration module was sourced above (wakeonlan_main_config),
# run it now (unless we're in DRY_RUN). In DRY_RUN show status instead.
# This keeps the step idempotent and consistent with the installer flow.
# ------------------------------------------------------------------
if declare -f wakeonlan_main_config >/dev/null 2>&1; then
    step "Configuring Wake-on-LAN (Ethernet)"

    if [ "${DRY_RUN:-false}" = "true" ]; then
        log_info "[DRY-RUN] Would auto-configure Wake-on-LAN for wired interfaces"

        # Try to show what would be done by printing helper status output (if present)
        WOL_HELPER="$(cd "$SCRIPT_DIR/.." && pwd)/Scripts/wakeonlan.sh"
        if [ -x "$WOL_HELPER" ]; then
            bash "$WOL_HELPER" --status 2>&1 | sed 's/^/  /'
        else
            log_warn "Wake-on-LAN helper not found at $WOL_HELPER"
        fi
    else
        # Non-dry run: call the integration entrypoint which handles enabling
        wakeonlan_main_config || log_warn "wakeonlan_main_config reported issues"
    fi
fi

# Step: Run Distribution-Specific Configuration
# This replaces the numbered scripts with unified distribution-specific modules
# Note: Distro configs were already sourced earlier for package lists
if [ "$DRY_RUN" = false ]; then
    step "Running Distribution-Specific Configuration"

    case "$DISTRO_ID" in
        "arch")
            if declare -f arch_main_config >/dev/null 2>&1; then
                arch_main_config
            else
                log_warn "Arch configuration module not found"
            fi
            ;;
        "fedora")
            if declare -f fedora_main_config >/dev/null 2>&1; then
                fedora_main_config
            else
                log_warn "Fedora configuration module not found"
            fi
            ;;
        "debian"|"ubuntu")
            if declare -f debian_main_config >/dev/null 2>&1; then
                debian_main_config
            else
                log_warn "Debian/Ubuntu configuration module not found"
            fi
            ;;
        *)
            log_warn "No specific configuration module for $DISTRO_ID"
            ;;
    esac
fi

# Step: Run Desktop Environment Configuration
if [ "$INSTALL_MODE" != "server" ]; then
    step "Configuring Desktop Environment"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure desktop environment: ${XDG_CURRENT_DESKTOP:-None}"
    else
        case "${XDG_CURRENT_DESKTOP:-}" in
            *"KDE"*)
                if [ -f "$SCRIPTS_DIR/kde_config.sh" ]; then
                    source "$SCRIPTS_DIR/kde_config.sh"
                    kde_main_config
                else
                    log_warn "KDE configuration module not found"
                fi
                ;;
            *"GNOME"*)
                if [ -f "$SCRIPTS_DIR/gnome_config.sh" ]; then
                    source "$SCRIPTS_DIR/gnome_config.sh"
                    gnome_main_config
                else
                    log_warn "GNOME configuration module not found"
                fi
                ;;
            *)
                log_info "No specific desktop environment configuration for ${XDG_CURRENT_DESKTOP:-None}"
                ;;
        esac
    fi
fi

# Step: Run Security Configuration
step "Configuring Security Features"

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would configure security features"
else
    if [ -f "$SCRIPTS_DIR/security_config.sh" ]; then
        source "$SCRIPTS_DIR/security_config.sh"
        security_main_config
    else
        log_warn "Security configuration module not found"
    fi
fi

# Step: Run Performance Optimization
step "Applying Performance Optimizations"

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would apply performance optimizations"
else
    if [ -f "$SCRIPTS_DIR/performance_config.sh" ]; then
        source "$SCRIPTS_DIR/performance_config.sh"
        performance_main_config
    else
        log_warn "Performance configuration module not found"
    fi
fi

# Step: Run Maintenance Setup
step "Setting up Maintenance Tools"

if [ "$DRY_RUN" = true ]; then
    log_info "[DRY-RUN] Would set up maintenance tools"
else
    if [ -f "$SCRIPTS_DIR/maintenance_config.sh" ]; then
        source "$SCRIPTS_DIR/maintenance_config.sh"
        maintenance_main_config
    else
        log_warn "Maintenance configuration module not found"
    fi
fi

# Step: Run Gaming Configuration (if applicable)
if [ "$INSTALL_MODE" != "server" ] && [ "${INSTALL_GAMING:-false}" = "true" ]; then
    step "Configuring Gaming Environment"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure gaming environment"
    else
        if [ -f "$SCRIPTS_DIR/gaming_config.sh" ]; then
            source "$SCRIPTS_DIR/gaming_config.sh"
            gaming_main_config
        else
            log_warn "Gaming configuration module not found"
        fi
    fi
fi

# 5. Finalization
step "Finalizing Installation"

if [ "$DRY_RUN" = false ]; then
    final_cleanup
fi

# Detect system info for installation summary (if power_config available)
if declare -f detect_system_info >/dev/null 2>&1; then
    detect_system_info
fi

# Source and show installation summary with reboot prompt
if [ -f "$SCRIPTS_DIR/installation_summary.sh" ]; then
    source "$SCRIPTS_DIR/installation_summary.sh"
    show_installation_summary
else
    prompt_reboot
fi
