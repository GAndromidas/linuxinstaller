#!/bin/bash
set -uo pipefail

# =============================================================================
# LinuxInstaller - Unified Post-Installation Script
# Supports: Arch Linux, Fedora, Debian, Ubuntu
# =============================================================================

# --- Configuration & Paths ---
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
PROGRAMS_YAML="$CONFIGS_DIR/programs.yaml"
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

# --- Global Variables ---
# Flags
VERBOSE=false
DRY_RUN=false

# Track installed helpers to clean up later
FIGLET_INSTALLED_BY_SCRIPT=false
GUM_INSTALLED_BY_SCRIPT=false
YQ_INSTALLED_BY_SCRIPT=false

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
    installs packages via YAML configuration, and applies tweaks.
    Supports Arch, Fedora, Debian, and Ubuntu.
EOF
  exit 0
}

# Ensure essential tools (gum, yq) are present
bootstrap_tools() {
    log_info "Bootstrapping installer tools..."

    # 1. GUM (UI)
    if ! command -v gum >/dev/null 2>&1; then
        echo "Installing gum for UI..."
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would install gum"
        else
            # Attempt to install gum based on distro
            if [ "$DISTRO_ID" == "arch" ]; then
                 sudo pacman -S --noconfirm gum >/dev/null 2>&1
            else
                 $PKG_INSTALL $PKG_NOCONFIRM gum >/dev/null 2>&1
            fi
            GUM_INSTALLED_BY_SCRIPT=true
        fi
    fi

    # 2. YQ (YAML Parser)
    if ! command -v yq >/dev/null 2>&1; then
        echo "Installing yq for configuration parsing..."
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would install yq"
        else
            if [ "$DISTRO_ID" == "arch" ]; then
                 sudo pacman -S --noconfirm go-yq >/dev/null 2>&1
            else
                 $PKG_INSTALL $PKG_NOCONFIRM yq >/dev/null 2>&1
            fi
            YQ_INSTALLED_BY_SCRIPT=true
        fi
    fi
}

cleanup_tools() {
    if [ "$DRY_RUN" = true ]; then return; fi
    log_info "Cleaning up temporary tools..."

    # Optional: Only remove if we really want to leave no trace.
    # if [ "$GUM_INSTALLED_BY_SCRIPT" = true ]; then remove_pkg gum; fi
    # if [ "$YQ_INSTALLED_BY_SCRIPT" = true ]; then remove_pkg yq; fi
}

# Package Installation Logic using yq and programs.yaml
install_package_group() {
    local section_path="$1"
    local title="$2"

    log_info "Processing package group: $title ($section_path)"

    if [ ! -f "$PROGRAMS_YAML" ]; then
         log_error "Config file not found: $PROGRAMS_YAML"
         return
    fi

    # Determine package types available for this distro
    local pkg_types="native"
    case "$DISTRO_ID" in
        arch)   pkg_types="native aur" ;;
        ubuntu) pkg_types="native snap flatpak" ;;
        *)      pkg_types="native flatpak" ;; # fedora, debian
    esac

    for type in $pkg_types; do
        # Construct yq query logic
        local query=""

        # Logic to handle different sections in YAML
        if [[ "$section_path" == "gaming" ]]; then
            # Gaming: .gaming.<distro>.<type>
            query=".gaming.${DISTRO_ID}.${type}[]"
        elif [[ "$section_path" == "kde" || "$section_path" == "gnome" || "$section_path" == "cosmic" ]]; then
            # DE specific: .<distro>.<mode>.<de>.install[]
            # We use INSTALL_MODE if available, else standard
            local mode="${INSTALL_MODE:-standard}"
            query=".${DISTRO_ID}.${mode}.${section_path}.install[]"
        else
            # Standard modes: .<distro>.<mode>.<type>
            query=".${DISTRO_ID}.${section_path}.${type}[]"
        fi

        # Read packages into array
        mapfile -t packages < <(yq e "$query" "$PROGRAMS_YAML" 2>/dev/null)

        # Filter out nulls or empty lines
        packages=("${packages[@]//null/}")

        if [ ${#packages[@]} -eq 0 ] || [ -z "${packages[0]}" ]; then
            continue
        fi

        log_info "Installing $type packages for $title..."

        if [ "$DRY_RUN" = true ]; then
             gum style --foreground 212 "[DRY-RUN] Would install ($type): ${packages[*]}"
             continue
        fi

        # Installation Command Construction
        local install_cmd=""
        case "$type" in
            native)
                install_cmd="$PKG_INSTALL $PKG_NOCONFIRM"
                ;;
            aur)
                # Check for AUR helper (yay/paru)
                if command -v yay >/dev/null; then install_cmd="yay -S --noconfirm"
                elif command -v paru >/dev/null; then install_cmd="paru -S --noconfirm"
                else
                    log_warn "No AUR helper found. Skipping AUR packages."
                    continue
                fi
                ;;
            flatpak)
                if ! command -v flatpak >/dev/null; then
                     log_warn "Flatpak not installed. Attempting to install it..."
                     sudo $PKG_INSTALL $PKG_NOCONFIRM flatpak >> "$INSTALL_LOG" 2>&1
                fi
                install_cmd="flatpak install flathub -y"
                ;;
            snap)
                install_cmd="sudo snap install"
                ;;
        esac

        # Run installation with spinner
        gum spin --spinner dot --title "Installing $type packages ($title)..." -- bash -c "$install_cmd ${packages[*]}" >> "$INSTALL_LOG" 2>&1

        if [ $? -eq 0 ]; then
            log_success "Installed ($type): ${packages[*]}"
        else
            log_error "Failed to install some ($type) packages. Check log."
        fi
    done
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

# Bootstrap UI tools
bootstrap_tools

# 3. Welcome & Resume Check
clear
gum style --border double --margin "1 2" --padding "1 4" --border-foreground 212 "LinuxInstaller: Unified Setup" "Detected System: $PRETTY_NAME" "Detected DE: ${XDG_CURRENT_DESKTOP:-None}"

# Check for previous state (Resume capability)
if [ "$DRY_RUN" = false ]; then
    show_resume_menu
else
    log_warn "Dry-Run Mode Active: No changes will be applied."
fi

# 4. Mode Selection
# Only ask if we are not resuming or if mode isn't set in state (state logic handles resuming steps, not config variables currently, so we re-ask or save config. For simplicity, we re-ask if starting fresh)

if ! is_step_complete "setup_mode"; then
    MODE=$(gum choose --header "Select Installation Mode" "Standard" "Minimal" "Server" "Custom")

    # Save mode for reference (not fully persistent in this simple state file, but good for flow)
    export INSTALL_MODE="$(echo "$MODE" | tr '[:upper:]' '[:lower:]')"

    if [ "$MODE" == "Custom" ]; then
        # In custom, maybe we start with minimal and add groups
        INSTALL_MODE="minimal"
        CUSTOM_GROUPS=$(gum choose --no-limit --header "Select Add-ons" "Gaming" "Dev Tools" "Office")
    fi

    mark_step_complete "setup_mode"
fi

# 5. Core Execution Loop
# We define a list of logical steps.

# Step: System Update
if ! is_step_complete "system_update"; then
    step "Updating System Repositories"
    if [ "$DRY_RUN" = false ]; then
        gum spin --title "Updating system..." -- bash -c "$PKG_UPDATE $PKG_NOCONFIRM" >> "$INSTALL_LOG" 2>&1
    fi
    mark_step_complete "system_update"
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

    # Interactive prompt for optional Gaming if not explicitly chosen/excluded
    # (Only for Standard mode if not resuming)
    if [ "$INSTALL_MODE" == "standard" ] && [ -z "${CUSTOM_GROUPS:-}" ]; then
        if gum confirm "Install Gaming Package Suite?" --default=false; then
             install_package_group "gaming" "Gaming Suite"
        fi
    fi

    mark_step_complete "install_packages"
fi

# Step: Run Configuration Scripts
# Iterate over numbered scripts in scripts/ directory
# We skip common.sh and distro_check.sh as they are libraries

for script in "$SCRIPTS_DIR"/*.sh; do
    script_name=$(basename "$script")

    # Skip library files
    if [[ "$script_name" == "common.sh" || "$script_name" == "distro_check.sh" ]]; then
        continue
    fi

    step_id="script_${script_name%.*}"

    if ! is_step_complete "$step_id"; then
        step "Running: $script_name"

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would execute $script"
        else
            # Execute script
            # We source them to share environment variables
            # Wrap in subshell if isolation needed, but sourcing is better for shared vars
            ( source "$script" ) >> "$INSTALL_LOG" 2>&1

            if [ $? -eq 0 ]; then
                log_success "Finished $script_name"
                mark_step_complete "$step_id"
            else
                log_error "Script $script_name failed."
                if gum confirm "Continue despite failure?" --default=false; then
                    log_warn "Skipping failed step..."
                    mark_step_complete "$step_id" # Mark as done so we don't loop forever
                else
                    log_error "Installation aborted by user."
                    exit 1
                fi
            fi
        fi
    fi
done

# 6. Finalization
step "Finalizing Installation"
cleanup_tools

if [ "$DRY_RUN" = true ]; then
    gum style --foreground 212 "Dry-Run Complete. No changes were made."
else
    gum format --theme=dark "## Installation Complete!" "Your system is ready. Please reboot to ensure all changes take effect."
    prompt_reboot
fi
