#!/bin/bash
set -uo pipefail

# =============================================================================
# LinuxInstaller - Unified Post-Installation Script
# Supports: Arch Linux, Fedora, Debian, Ubuntu
# =============================================================================

# LinuxInstaller ASCII Art Function
show_linuxinstaller_ascii() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
     _     _                  ___           _        _ _
    | |   (_)_ __  _   ___  _|_ _|_ __  ___| |_ __ _| | | ___ _ __
    | |   | | '_ \| | | \ \/ /| || '_ \/ __| __/ _` | | |/ _ \ '__|
    | |___| | | | | |_| |>  < | || | | \__ \ || (_| | | |  __/ |
    |_____|_|_| |_|\__,_/_/\_\___|_| |_|___/\__\__,_|_|_|\___|_|
EOF
    echo -e "${RESET}"
}

# Show System Info in Bordered Box
show_system_info_box() {
    detect_system_info 2>/dev/null || true

    if supports_gum; then
        # Create bordered box with system information
        {
            gum style --foreground "$GUM_PRIMARY_FG" --bold "System Information"
            echo ""
            gum style --foreground "$GUM_BODY_FG" "OS:  ${DETECTED_OS:-$PRETTY_NAME}"
            gum style --foreground "$GUM_BODY_FG" "DE:  ${XDG_CURRENT_DESKTOP:-None}"
            gum style --foreground "$GUM_BODY_FG" "CPU: ${DETECTED_CPU:-Unknown}"
            gum style --foreground "$GUM_BODY_FG" "GPU: ${DETECTED_GPU:-Unknown}"
            gum style --foreground "$GUM_BODY_FG" "RAM: ${DETECTED_RAM:-Unknown}"
        } | gum style --border double --margin "1 2" --padding "1 2" --border-foreground "$GUM_BORDER_FG" 2>/dev/null || true
    else
        echo ""
        echo "System Information:"
        echo "-------------------"
        echo "OS:  ${DETECTED_OS:-$PRETTY_NAME}"
        echo "DE:  ${XDG_CURRENT_DESKTOP:-None}"
        echo "CPU: ${DETECTED_CPU:-Unknown}"
        echo "GPU: ${DETECTED_GPU:-Unknown}"
        echo "RAM: ${DETECTED_RAM:-Unknown}"
        echo "-------------------"
    fi
}

# Enhanced Menu Function
show_menu() {
    show_linuxinstaller_ascii

    # Try to ensure gum is available; bootstrap_tools should have run already
    # but this is a last-resort attempt (quiet failures are acceptable)
    if ! supports_gum; then
        log_info "gum not detected; UI may fall back to text mode"
    fi

    echo ""

    # If gum is available and we have an interactive TTY, try to gum-based UI.
    # If gum fails or we don't have a TTY, gracefully fall back to a simple text menu.
    if supports_gum && [ -t 0 ]; then
        # Show System Information in Bordered Box
        show_system_info_box
        echo ""

        # Try interactive gum menu; if it fails or returns no selection, fall back
        local choice
        choice=$(gum choose --height 10 --header "Please select an installation mode:" \
            "1. Standard - Complete setup with all recommended packages" \
            "2. Minimal - Essential tools only for lightweight installations" \
            "3. Server - Headless server configuration" \
            "4. Exit" \
            --cursor.foreground "$GUM_PRIMARY_FG" --cursor "→" --header.foreground "$GUM_PRIMARY_FG" 2>/dev/null) || true

        # If gum failed or returned nothing, warn and fall through to text menu
        if [ -n "$choice" ]; then
            case "$choice" in
                "1. Standard - Complete setup with all recommended packages")
                    export INSTALL_MODE="standard" ;;
                "2. Minimal - Essential tools only for lightweight installations")
                    export INSTALL_MODE="minimal" ;;
                "3. Server - Headless server configuration")
                    export INSTALL_MODE="server" ;;
                "4. Exit")
                    echo "Exiting..." ; exit 0 ;;
                *)
                    log_warn "Gum returned an unexpected choice: '$choice' - falling back to text menu." ;;
            esac

            # If gum returned a valid choice, print a friendly confirmation, ask about gaming, and return
            if [ -n "${INSTALL_MODE:-}" ]; then
                echo ""
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "You selected: $choice" 2>/dev/null || true
                echo ""
                # Prompt for Gaming immediately after selection (default Yes in gum)
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
        else
            log_warn "Gum UI not available or failed; falling back to text menu."
        fi
    fi

    # Fallback plain-text menu
    echo ""
    # Show System Information in Bordered Box (same as gum version)
    show_system_info_box
    echo ""

    local text_choice
    while true; do
        echo "Please select an installation mode:"
        echo "  1) Standard - Complete setup with all recommended packages"
        echo "  2) Minimal - Essential tools only for lightweight installations"
        echo "  3) Server - Headless server configuration"
        echo "  4) Exit"
        read -r -p "Enter choice [1-4]: " text_choice

        case "$text_choice" in
            1) export INSTALL_MODE="standard" ; break ;;
            2) export INSTALL_MODE="minimal" ; break ;;
            3) export INSTALL_MODE="server" ; break ;;
            4) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice, please try again." ;;
        esac
    done

    echo ""

    # Friendly selection message
    local friendly
    case "$INSTALL_MODE" in
        standard) friendly="Standard - Complete setup with all recommended packages" ;;
        minimal)  friendly="Minimal - Essential tools only for lightweight installations" ;;
        server)   friendly="Server - Headless server configuration" ;;
        *)        friendly="$INSTALL_MODE" ;;
    esac

    if supports_gum && [ -t 0 ]; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "You selected: $friendly" 2>/dev/null || true
    else
        echo "You selected: $friendly"
    fi

    # Prompt for Gaming immediately after selection when applicable (Standard/Minimal)
    if { [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; } && [ -z "${CUSTOM_GROUPS:-}" ]; then
        if supports_gum && [ -t 0 ]; then
            if gum confirm "Install Gaming Package Suite?" --default=true; then
                export INSTALL_GAMING=true
            else
                export INSTALL_GAMING=false
            fi
        elif [ -t 0 ]; then
            read -r -p "Install Gaming Package Suite? [Y/n]: " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
                export INSTALL_GAMING=true
            else
                export INSTALL_GAMING=false
            fi
        else
            # Non-interactive: default to not installing gaming packages to avoid surprises
            export INSTALL_GAMING=false
            log_info "Non-interactive mode; defaulting to not installing gaming packages"
        fi
    else
        # If custom groups include gaming, honor it uniformly
        if [[ "${CUSTOM_GROUPS:-}" == *"Gaming"* ]]; then
            export INSTALL_GAMING=true
        fi
    fi

    echo ""
}

# Color variables
BLUE='\033[0;34m'
RESET='\033[0m'

# --- Configuration & Paths ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
INSTALL_LOG="$HOME/.linuxinstaller.log"

# Ensure log file exists and start fresh for this run
touch "$INSTALL_LOG"

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

# Installation state
STATE_FILE="$HOME/.linuxinstaller.state"
mkdir -p "$(dirname "$STATE_FILE")"

# --- Helper Functions ---

show_help() {
  cat << EOF
LinuxInstaller - Unified Post-Install Script

USAGE:
    sudo ./install.sh [OPTIONS]

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

LOG FILE:
    Installation log saved to: ~/.linuxinstaller.log

EOF
  exit 0
}

# Ensure essential tools (gum) are present and usable
bootstrap_tools() {
    log_info "Bootstrapping installer tools..."

    # Try to proceed even when network is flaky, but warn if no internet
    # Use a non-fatal ping check here (check_internet exits the script on failure,
    # so we avoid calling it to allow the installer to continue in degraded mode).
    if ! ping -c 1 -W 5 google.com >/dev/null 2>&1; then
        log_warn "No internet connection detected. Some helper installs may fail or be skipped."
    fi

    # 1. GUM (UI) - try package manager, then fallback to binary download
    if ! supports_gum; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would install gum for UI"
        else
            log_info "Installing gum for UI..."
            # Try package manager first
            if [ "$DISTRO_ID" == "arch" ]; then
                if sudo pacman -S --noconfirm gum >/dev/null 2>&1; then
                    log_success "Installed gum via pacman"
                    GUM_INSTALLED_BY_SCRIPT=true
                    # Refresh detection so wrapper/short-circuits know gum is now available
                    supports_gum >/dev/null 2>&1 || true
                fi
            else
                if $PKG_INSTALL $PKG_NOCONFIRM gum >/dev/null 2>&1; then
                    log_success "Installed gum via package manager"
                    GUM_INSTALLED_BY_SCRIPT=true
                    supports_gum >/dev/null 2>&1 || true
                fi
            fi

            # If not available from packages, try binary as fallback
            if ! supports_gum; then
                log_info "Attempting to download gum binary as fallback..."
                if curl -fsSL "https://github.com/charmbracelet/gum/releases/latest/download/gum-linux-amd64" -o /tmp/gum >/dev/null 2>&1 && sudo mv /tmp/gum /usr/local/bin/gum && sudo chmod +x /usr/local/bin/gum; then
                    log_success "Installed gum binary to /usr/local/bin/gum"
                    GUM_INSTALLED_BY_SCRIPT=true
                    supports_gum >/dev/null 2>&1 || true
                else
                    log_warn "Failed to install gum via package manager or download. UI will fall back to basic output."
                fi
            fi
        fi
    fi

    # YQ & FIGLET auto-installation disabled per user preference (not installing yq or figlet)
    # YAML-driven features may still work if yq is already provided by the system.
    # Banner output will use fallback if figlet is not installed.
    # Report what is available
    if supports_gum; then
        log_info "UX helper available: gum"
    fi
}



# Package Installation Logic (robust parsing of many YAML shapes)
install_package_group() {
    local section_path="$1"
    local title="$2"
    local mode="${INSTALL_MODE:-standard}"

    log_info "Processing package group: $title ($section_path)"

    # Determine package types available for this distro
    local pkg_types
    case "$DISTRO_ID" in
        arch)   pkg_types="native aur flatpak" ;;
        ubuntu) pkg_types="native snap flatpak" ;;
        *)      pkg_types="native flatpak" ;; # fedora, debian
    esac

    for type in $pkg_types; do
        log_info "Collecting package definitions (type: $type) for '$section_path'..."

        # Try distro-provided package function first (preferred)
        local packages=()
        if declare -f distro_get_packages >/dev/null 2>&1; then
            # distro_get_packages should print one package per line; capture and normalize
            mapfile -t tmp < <(distro_get_packages "$section_path" "$type" 2>/dev/null || true)
            mapfile -t packages < <(printf "%s\n" "${tmp[@]}" | sed '/^[[:space:]]*null[[:space:]]*$/d' | sed '/^[[:space:]]*$/d')
        else
            # YAML-driven discovery has been removed.
            # Package lists must be provided by the distro module via 'distro_get_packages()'.
            log_info "No distro package provider available; skipping deprecated YAML fallback for $title"
            continue
        fi

        if [ ${#packages[@]} -eq 0 ]; then
            log_info "No $type packages found for $title"
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

        # Pretty output of what will be installed
        if supports_gum; then
            gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "Installing ($type) for $title: ${packages[*]}"
        else
            log_info "Installing ($type) for $title: ${packages[*]}"
        fi

        if [ "$DRY_RUN" = true ]; then
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "[DRY-RUN] Would install ($type): ${packages[*]}"
            else
                log_info "[DRY-RUN] Would install ($type): ${packages[*]}"
            fi
            continue
        fi

        # Installation command selection
        local install_cmd=""
        case "$type" in
            native)
                install_cmd="$PKG_INSTALL $PKG_NOCONFIRM"
                ;;
            aur)
                if command -v yay >/dev/null 2>&1; then
                    install_cmd="yay -S --noconfirm"
                elif command -v paru >/dev/null 2>&1; then
                    install_cmd="paru -S --noconfirm"
                else
                    log_warn "No AUR helper found. Skipping AUR packages."
                    continue
                fi
                ;;
            flatpak)
                if ! command -v flatpak >/dev/null 2>&1; then
                    log_warn "Flatpak not installed. Attempting to install it..."
                    $PKG_INSTALL $PKG_NOCONFIRM flatpak >> "$INSTALL_LOG" 2>&1 || true
                fi
                install_cmd="flatpak install flathub -y"
                ;;
            snap)
                install_cmd="sudo snap install"
                ;;
        esac

        # Safely build package arguments (quoting)
        local pkg_args=""
        for p in "${packages[@]}"; do
            p="$(echo "$p" | xargs)" # trim
            pkg_args="$pkg_args $(printf '%q' "$p")"
        done

        # Execute installation (special handling for flatpaks so output is visible)
        if [ "$type" = "flatpak" ]; then
            # Announce minimal header; keep verbose details in the log to avoid noisy console output
            if supports_gum; then
                gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "Installing Flatpak packages for $title..." 2>/dev/null || true
            else
                log_info "Installing Flatpak packages for $title..."
            fi

            # Install flatpaks one-by-one, suppressing flatpak's verbose output and showing a compact status per package
            local failed_packages=()
            for pkg in "${packages[@]}"; do
                pkg="$(echo "$pkg" | xargs)"  # trim whitespace
                if supports_gum; then
                    # Use gum spinner while running the install; flatpak output is redirected to the log
                    if gum spin --spinner dot --title "Flatpak: $pkg" -- bash -lc "$install_cmd $(printf '%q' "$pkg")" >> "$INSTALL_LOG" 2>&1; then
                        gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✔ $pkg Installed" 2>/dev/null || true
                    else
                        gum style --margin "0 4" --foreground "$GUM_ERROR_FG" "✗ $pkg Failed (see $INSTALL_LOG)" 2>/dev/null || true
                        failed_packages+=("$pkg")
                    fi
                else
                    # Non-gum terminals: print a concise one-line status per package and keep detailed output in the log
                    printf "%-60s" "Installing Flatpak: $pkg"
                    if bash -lc "$install_cmd $(printf '%q' "$pkg")" >> "$INSTALL_LOG" 2>&1; then
                        printf "${GREEN} ✔ Installed${RESET}\n"
                    else
                        printf "${RED} ✗ Failed${RESET}\n"
                        failed_packages+=("$pkg")
                    fi
                fi
            done

            if [ ${#failed_packages[@]} -eq 0 ]; then
                log_success "Installed (flatpak): ${packages[*]}"
            else
                log_error "Failed to install (flatpak): ${failed_packages[*]}. Check log: $INSTALL_LOG"
            fi
        else
            if supports_gum; then
                gum spin --spinner dot --title "Installing $type packages ($title)..." -- bash -lc "$install_cmd $pkg_args" >> "$INSTALL_LOG" 2>&1
            else
                log_info "Running: $install_cmd $pkg_args"
                bash -lc "$install_cmd $pkg_args" >> "$INSTALL_LOG" 2>&1
            fi

            if [ $? -eq 0 ]; then
                log_success "Installed ($type): ${packages[*]}"
            else
                log_error "Failed to install some ($type) packages. Check log: $INSTALL_LOG"
            fi
        fi
    done
}

# --- User Shell & Config Setup ---

configure_user_shell_and_configs() {
    step "Configuring Zsh and user-level configs (zsh, starship, fastfetch)"
    local target_user="${SUDO_USER:-$USER}"
    local home_dir
    home_dir="$(eval echo ~${target_user})"
    local cfg_dir="$CONFIGS_DIR/$DISTRO_ID"

    log_info "Ensuring zsh and related packages are installed (zsh, zsh-autosuggestions, zsh-syntax-highlighting, starship, fastfetch)"
    install_pkg zsh zsh-autosuggestions zsh-syntax-highlighting starship fastfetch || true

    # Deploy .zshrc (backup if present)
    if [ -f "$cfg_dir/.zshrc" ]; then
        if [ -f "$home_dir/.zshrc" ]; then
            local backup_file="$home_dir/.zshrc.backup.$(date +%s)"
            cp -a "$home_dir/.zshrc" "$backup_file" || true
            log_info "Backed up existing .zshrc to $backup_file"
        fi
        cp -a "$cfg_dir/.zshrc" "$home_dir/.zshrc" || log_warn "Failed to copy .zshrc"
        sudo chown "$target_user:$target_user" "$home_dir/.zshrc" || true
        log_success ".zshrc deployed to $home_dir/.zshrc"
    else
        log_info "No distro .zshrc found at $cfg_dir/.zshrc; skipping"
    fi

    # Deploy starship config
    if [ -f "$cfg_dir/starship.toml" ]; then
        mkdir -p "$home_dir/.config"
        cp -a "$cfg_dir/starship.toml" "$home_dir/.config/starship.toml" || log_warn "Failed to copy starship.toml"
        sudo chown "$target_user:$target_user" "$home_dir/.config/starship.toml" || true
        log_success "starship.toml deployed to $home_dir/.config/starship.toml"
    else
        log_info "No starship.toml found at $cfg_dir/starship.toml; skipping"
    fi

    # Deploy fastfetch config
    if [ -f "$cfg_dir/config.jsonc" ]; then
        mkdir -p "$home_dir/.config/fastfetch"
        cp -a "$cfg_dir/config.jsonc" "$home_dir/.config/fastfetch/config.jsonc" || log_warn "Failed to copy fastfetch config"
        sudo chown -R "$target_user:$target_user" "$home_dir/.config/fastfetch" || true
        log_success "fastfetch configuration deployed to $home_dir/.config/fastfetch/config.jsonc"
    else
        log_info "No fastfetch config found at $cfg_dir/config.jsonc; skipping"
    fi

    # Set default shell for target user (skip chsh to avoid hang)
    if command -v zsh >/dev/null 2>&1; then
        log_info "Zsh is installed. Default shell can be changed manually with: chsh -s zsh"
        log_info "Skipping automatic shell change to prevent installation hang"
    else
        log_warn "zsh not installed; skipping shell change"
    fi

    return 0
}

# --- Final Cleanup ---
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
                if sudo $PKG_REMOVE $PKG_NOCONFIRM "$pkg" >> "$INSTALL_LOG" 2>&1; then
                    log_success "Removed $pkg via package manager"
                else
                    # Fallback: try removing binary placed under /usr/local/bin
                    if [ -f "/usr/local/bin/$pkg" ]; then
                        sudo rm -f "/usr/local/bin/$pkg" && log_success "Removed /usr/local/bin/$pkg" || log_warn "Failed to remove /usr/local/bin/$pkg"
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
                if sudo $PKG_REMOVE $PKG_NOCONFIRM "$pkg" >> "$INSTALL_LOG" 2>&1; then
                    log_success "Removed $pkg via package manager"
                else
                    if [ -f "/usr/local/bin/$pkg" ]; then
                        sudo rm -f "/usr/local/bin/$pkg" && log_success "Removed /usr/local/bin/$pkg" || log_warn "Failed to remove /usr/local/bin/$pkg"
                    else
                        log_warn "Failed to remove $pkg via package manager"
                    fi
                fi
            done
        fi
    fi
}
# --- State Management ---

# Function to mark step as completed
mark_step_complete() {
    local step_name="$1"
    local friendly="${CURRENT_STEP_MESSAGE:-$step_name}"
    if ! grep -q "^$step_name$" "$STATE_FILE" 2>/dev/null; then
        echo "$step_name" >> "$STATE_FILE"
    fi
    # Show a concise, friendly success message for the completed step
    log_success "$friendly"
    # Clear the saved friendly message
    CURRENT_STEP_MESSAGE=""
}

# Function to check if step was completed
is_step_complete() {
    local step_name="$1"
    [ -f "$STATE_FILE" ] && grep -q "^$step_name$" "$STATE_FILE"
}

# Function to clear state
clear_state() {
    rm -f "$STATE_FILE"
}

# Resume menu
show_resume_menu() {
    if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
        log_info "Previous installation detected. The following steps were completed:"

        if supports_gum; then
            echo ""
            gum style --margin "0 2" --foreground "$GUM_PRIMARY_FG" --bold "Completed steps:"
            while IFS= read -r step; do
                 gum style --margin "0 4" --foreground "$GUM_SUCCESS_FG" "✓ $step"
            done < "$STATE_FILE"
            echo ""

            if gum confirm --default=true "Resume installation from where you left off?"; then
                log_success "Resuming installation..."
                return 0
            else
                if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
                    clear_state
                    log_info "Starting fresh installation..."
                    return 0
                else
                    log_info "Installation cancelled by user."
                    exit 0
                fi
            fi
        else
            while IFS= read -r step; do
                 echo -e "  [DONE] $step"
            done < "$STATE_FILE"

            read -r -p "Resume installation? [Y/n]: " response
            if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ || -z "$response" ]]; then
                log_success "Resuming installation..."
                return 0
            else
                read -r -p "Start fresh installation? [y/N]: " response
                if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
                    clear_state
                    log_info "Starting fresh installation..."
                    return 0
                else
                    log_info "Installation cancelled by user."
                    exit 0
                fi
            fi
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

# 3. Welcome & Resume Check
clear
# Show System Information in Bordered Box
show_system_info_box
echo ""

# Check for previous state (Resume capability)
if [ "$DRY_RUN" = false ]; then
    if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
        show_resume_menu
    else
        log_info "No previous installation state found. Starting fresh."
    fi
else
    log_warn "Dry-Run Mode Active: No changes will be applied."
fi

# 4. Mode Selection
# Ensure that user is always prompted in interactive runs (so that menu appears on ./install.sh).
# For non-interactive runs (CI, scripts), preserve existing behavior by selecting a sensible default.
if [ "$DRY_RUN" = false ]; then
    show_menu
    mark_step_complete "setup_mode"
else
    log_warn "Dry-Run Mode Active: No changes will be applied."
fi

# 4. Mode Selection
# Ensure the user is always prompted in interactive runs (so the menu appears on ./install.sh).
# For non-interactive runs (CI, scripts), preserve existing behavior by selecting a sensible default.
if [ -t 0 ]; then
    show_menu
    mark_step_complete "setup_mode"
else
    # Non-interactive: only set a default mode if none exists to avoid prompting
    if ! is_step_complete "setup_mode"; then
        export INSTALL_MODE="${INSTALL_MODE:-standard}"
        log_info "Non-interactive: defaulting to install mode: $INSTALL_MODE"
        mark_step_complete "setup_mode"
    fi
fi

# 5. Core Execution Loop
# We define a list of logical steps.

# Step: System Update
if ! is_step_complete "system_update"; then
    step "Updating System Repositories"
    if [ "$DRY_RUN" = false ]; then
        if supports_gum; then
            # Use gum spinner when available; if it fails fall back to the direct update command
            gum spin --title "Updating system..." -- bash -c "$PKG_UPDATE $PKG_NOCONFIRM" >> "$INSTALL_LOG" 2>&1 || { log_warn "gum spinner failed; falling back to direct update"; bash -c "$PKG_UPDATE $PKG_NOCONFIRM" >> "$INSTALL_LOG" 2>&1; }
        else
            # No gum available; run the update directly
            bash -c "$PKG_UPDATE $PKG_NOCONFIRM" >> "$INSTALL_LOG" 2>&1
        fi
    fi
    mark_step_complete "system_update"
fi

# Step: Pacman Configuration (Arch Linux only)
if [ "$DISTRO_ID" == "arch" ] && ! is_step_complete "pacman_config"; then
    step "Configuring Pacman Optimizations"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure pacman optimizations (parallel downloads, color, ILoveCandy)"
    else
        # Automatic speedtest installation removed — parallel downloads will be fixed to 10.
        # (Removing the speedtest dependency and dynamic adjustments per user request.)

        # Dynamic network speed detection removed — parallel downloads will remain fixed (10).
        # Per configuration decision, we will not change parallel downloads dynamically.

        configure_pacman() {
            step "Configuring pacman optimizations"

            # Use a fixed number of parallel downloads (10) — no speed-based adjustments
            local parallel_downloads=10

            # Handle ParallelDownloads - works whether commented or uncommented
            if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
                # Line is commented, uncomment and set value
                sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
                log_success "Uncommented and set ParallelDownloads = $parallel_downloads"
            elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
                # Line exists and is active, update value
                sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
                log_success "Updated ParallelDownloads = $parallel_downloads"
            else
                # Line doesn't exist at all, add it
                sudo sed -i "/^\[options\]/a ParallelDownloads = $parallel_downloads" /etc/pacman.conf
                log_success "Added ParallelDownloads = $parallel_downloads"
            fi

            # Handle Color setting
            if grep -q "^#Color" /etc/pacman.conf; then
                sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
                log_success "Uncommented Color setting"
            fi

            # Handle VerbosePkgLists setting
            if grep -q "^#VerbosePkgLists" /etc/pacman.conf; then
                sudo sed -i 's/^#VerbosePkgLists/VerbosePkgLists/' /etc/pacman.conf
                log_success "Uncommented VerbosePkgLists setting"
            fi

            # Add ILoveCandy if not already present
            if ! grep -q "^ILoveCandy" /etc/pacman.conf; then
                sudo sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
                log_success "Added ILoveCandy setting"
            fi

            # Enable multilib if not already enabled
            if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
                echo -e "\n[multilib]\nInclude = /etc/pacman.d/mirrorlist" | sudo tee -a /etc/pacman.conf >/dev/null
                log_success "Enabled multilib repository"
            else
                log_success "Multilib repository already enabled"
            fi

            echo ""
        }

        # Execute pacman configuration
        configure_pacman
    fi

    mark_step_complete "pacman_config"
fi

# Step: Run Distro System Preparation (install essentials, etc.)
# Run distro-specific system preparation early so essential helpers are present
# before package installation and mark the step complete to avoid duplication.
DSTR_PREP_FUNC="${DISTRO_ID}_system_preparation"
DSTR_PREP_STEP="${DSTR_PREP_FUNC}"
if declare -f "$DSTR_PREP_FUNC" >/dev/null 2>&1 && ! is_step_complete "$DSTR_PREP_STEP"; then
    step "Running system preparation for $DISTRO_ID"
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run $DSTR_PREP_FUNC"
    else
        if ! "$DSTR_PREP_FUNC"; then
            log_warn "$DSTR_PREP_FUNC reported issues (see $INSTALL_LOG)"
        fi
    fi
    mark_step_complete "$DSTR_PREP_STEP"
fi

# Install distro-provided 'essential' group first (if present)
# Ensures essentials get installed before the main package groups.
if ! is_step_complete "install_essentials"; then
    install_package_group "essential" "Essential Packages"
    mark_step_complete "install_essentials"
fi

# Step: Configure Power Management (power-profiles-daemon / cpupower / tuned)
if ! is_step_complete "configure_power"; then
    step "Configuring Power Management"
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure power management (power-profiles-daemon / cpupower / tuned)"
    else
        if declare -f configure_power_management >/dev/null 2>&1; then
            configure_power_management || log_warn "configure_power_management reported issues (see $INSTALL_LOG)"
        else
            log_warn "configure_power_management not defined"
        fi
    fi
    mark_step_complete "configure_power"
fi

# Step: Configure shell & user configs (zsh, starship, fastfetch)
if ! is_step_complete "configure_shell"; then
    step "Configuring Zsh and user-level configs"
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure Zsh and user config files (copy .zshrc, starship.toml, fastfetch config)"
    else
        if declare -f configure_user_shell_and_configs >/dev/null 2>&1; then
            configure_user_shell_and_configs || log_warn "configure_user_shell_and_configs reported issues (see $INSTALL_LOG)"
        else
            log_warn "configure_user_shell_and_configs not defined"
        fi
    fi
    mark_step_complete "configure_shell"
fi

# Step: Install Packages based on Mode
if ! is_step_complete "install_packages"; then
    step "Installing Packages ($INSTALL_MODE)"

    # Install the main group (standard/minimal/server)
    install_package_group "$INSTALL_MODE" "Base System"

    # Install Desktop Environment Specific Packages
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "$INSTALL_MODE" != "server" ]]; then
        DE_KEY=$(echo "$XDG_CURRENT_DESKTOP" | tr '[:upper:]' '[:lower:]')
        # Normalize DE key if needed (e.g. pop -> gnome/cosmic?)
        if [[ "$DE_KEY" == *"kde"* ]]; then DE_KEY="kde"; fi
        if [[ "$DE_KEY" == *"gnome"* ]]; then DE_KEY="gnome"; fi

        step "Installing Desktop Environment Packages ($DE_KEY)"
        install_package_group "$DE_KEY" "$XDG_CURRENT_DESKTOP Environment"
    fi

    # Handle Custom Addons if any (rudimentary handling)
    if [[ "${CUSTOM_GROUPS:-}" == *"Gaming"* ]]; then
        install_package_group "gaming" "Gaming Suite"
    fi

    # Use the gaming decision made at menu time (if applicable)
    if { [ "$INSTALL_MODE" == "standard" ] || [ "$INSTALL_MODE" == "minimal" ]; } && [ -z "${CUSTOM_GROUPS:-}" ]; then
        if [ "${INSTALL_GAMING:-false}" = "true" ]; then
            install_package_group "gaming" "Gaming Suite"
        fi
    fi

    mark_step_complete "install_packages"
fi

# ------------------------------------------------------------------
# Wake-on-LAN auto-configuration step
#
# If the wakeonlan integration module was sourced above (wakeonlan_main_config),
# run it now (unless we're in DRY_RUN). In DRY_RUN show status instead.
# This keeps the step idempotent and consistent with the installer flow.
# ------------------------------------------------------------------
if declare -f wakeonlan_main_config >/dev/null 2>&1; then
    if ! is_step_complete "wakeonlan_setup"; then
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

            mark_step_complete "wakeonlan_setup"
        else
            # Non-dry run: call the integration entrypoint which handles enabling and marking
            wakeonlan_main_config || log_warn "wakeonlan_main_config reported issues (see $INSTALL_LOG)"
        fi
    fi
fi

# Step: Run Distro System Preparation (install essentials, etc.)
# (system preparation logic moved earlier in the flow)

# Step: Run Distribution-Specific Configuration
# This replaces the numbered scripts with unified distribution-specific modules
if ! is_step_complete "distro_config"; then
    step "Running Distribution-Specific Configuration"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run distribution-specific configuration for $DISTRO_ID"
    else
        case "$DISTRO_ID" in
            "arch")
                if [ -f "$SCRIPTS_DIR/arch_config.sh" ]; then
                    source "$SCRIPTS_DIR/arch_config.sh"
                    arch_main_config
                else
                    log_warn "Arch configuration module not found"
                fi
                ;;
            "fedora")
                if [ -f "$SCRIPTS_DIR/fedora_config.sh" ]; then
                    source "$SCRIPTS_DIR/fedora_config.sh"
                    fedora_main_config
                else
                    log_warn "Fedora configuration module not found"
                fi
                ;;
            "debian"|"ubuntu")
                if [ -f "$SCRIPTS_DIR/debian_config.sh" ]; then
                    source "$SCRIPTS_DIR/debian_config.sh"
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
    mark_step_complete "distro_config"
fi

# Step: Run Desktop Environment Configuration
if ! is_step_complete "de_config" && [ "$INSTALL_MODE" != "server" ]; then
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
    mark_step_complete "de_config"
fi

# Step: Run Security Configuration
if ! is_step_complete "security_config"; then
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
    mark_step_complete "security_config"
fi

# Step: Run Performance Optimization
if ! is_step_complete "performance_config"; then
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
    mark_step_complete "performance_config"
fi

# Step: Run Maintenance Setup
if ! is_step_complete "maintenance_config"; then
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
    mark_step_complete "maintenance_config"
fi

# Step: Run Gaming Configuration (if applicable)
if ! is_step_complete "gaming_config" && [ "$INSTALL_MODE" != "server" ] && [ "${INSTALL_GAMING:-false}" = "true" ]; then
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
    mark_step_complete "gaming_config"
fi

# 6. Finalization
step "Finalizing Installation"

if [ "$DRY_RUN" = true ]; then
    if supports_gum; then
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" --bold "Dry-Run Complete. No changes were made."
    else
        log_info "Dry-Run Complete. No changes were made."
    fi
else
    if supports_gum; then
        gum format --theme=dark --foreground "$GUM_PRIMARY_FG" "## Installation Complete!"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Your system is ready. Performing final cleanup..."
    else
        log_success "Installation Complete! Performing final cleanup..."
    fi

    # Offer to remove temporary helpers the installer added
    final_cleanup

    if supports_gum; then
        gum format --theme=dark --foreground "$GUM_PRIMARY_FG" "## Done"
        gum style --margin "0 2" --foreground "$GUM_BODY_FG" "Your system is ready. Please reboot to ensure all changes take effect."
    else
        log_success "Done. Please reboot your system to ensure all changes take effect."
    fi

    prompt_reboot
fi
