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

# Enhanced Menu Function
show_menu() {
    show_linuxinstaller_ascii

    # Install gum silently if not present
    if ! command -v gum >/dev/null 2>&1; then
        log_info "Installing gum for beautiful UI..."
        if [ "$DISTRO_ID" == "arch" ]; then
            sudo pacman -S --noconfirm --needed gum >/dev/null 2>&1 || true
        else
            $PKG_INSTALL $PKG_NOCONFIRM gum >/dev/null 2>&1 || true
        fi
    fi

    # Install yq silently if not present
    if ! command -v yq >/dev/null 2>&1; then
        log_info "Installing yq for configuration parsing..."
        if [ "$DISTRO_ID" == "arch" ]; then
            sudo pacman -S --noconfirm --needed go-yq >/dev/null 2>&1 || true
        else
            $PKG_INSTALL $PKG_NOCONFIRM yq >/dev/null 2>&1 || true
        fi
    fi

    echo ""
    gum style --border double --margin "1 2" --padding "1 4" --foreground "$GUM_FG" --border-foreground "$GUM_FG" --bold "LinuxInstaller: Unified Setup" "Detected System: $PRETTY_NAME" "Detected DE: ${XDG_CURRENT_DESKTOP:-None}"
    echo ""

    # Enhanced menu with gum
    local choice
    choice=$(gum choose --height 10 --header "Please select an installation mode:" \
        "1. Standard - Complete setup with all recommended packages" \
        "2. Minimal - Essential tools only for lightweight installations" \
        "3. Server - Headless server configuration" \
        "4. Custom - Interactive selection of packages to install" \
        "5. Exit" \
        --cursor.foreground "$GUM_FG" --cursor "→" --header.foreground "$GUM_FG")

    case "$choice" in
        "1. Standard - Complete setup with all recommended packages")
            export INSTALL_MODE="standard"
            ;;
        "2. Minimal - Essential tools only for lightweight installations")
            export INSTALL_MODE="minimal"
            ;;
        "3. Server - Headless server configuration")
            export INSTALL_MODE="server"
            ;;
        "4. Custom - Interactive selection of packages to install")
            export INSTALL_MODE="custom"
            ;;
        "5. Exit")
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid choice. Please try again."
            show_menu
            ;;
    esac

    echo ""
    gum style --margin "0 2" --foreground "$GUM_FG" --bold "You selected: $choice"
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

# --- Global Variables ---
# Flags
VERBOSE=false
DRY_RUN=false
TOTAL_STEPS=0
CURRENT_STEP=0

# Track installed helpers to clean up later
FIGLET_INSTALLED_BY_SCRIPT=false
GUM_INSTALLED_BY_SCRIPT=false
YQ_INSTALLED_BY_SCRIPT=false

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
    installs packages via YAML configuration, and applies tweaks.
    Supports Arch, Fedora, Debian, and Ubuntu.
    Combines best practices from archinstaller, fedorainstaller, and debianinstaller.

INSTALLATION MODES:
    Standard        Complete setup with all recommended packages
    Minimal         Essential tools only for lightweight installations
    Server          Headless server configuration
    Custom          Interactive selection of packages to install

EXAMPLES:
    ./install.sh                Run with interactive prompts
    ./install.sh --verbose      Run with detailed output
    ./install.sh --dry-run      Preview changes without applying them

LOG FILE:
    Installation log saved to: ~/.linuxinstaller.log

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
             gum style --margin "0 2" --foreground "$GUM_FG" --bold "[DRY-RUN] Would install ($type): ${packages[*]}"
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

# --- State Management ---

# Function to mark step as completed
mark_step_complete() {
    local step_name="$1"
    if ! grep -q "^$step_name$" "$STATE_FILE" 2>/dev/null; then
        echo "$step_name" >> "$STATE_FILE"
    fi
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
            gum style --margin "0 2" --foreground "$GUM_FG" --bold "Completed steps:"
            while IFS= read -r step; do
                 gum style --margin "0 4" --foreground "$GUM_FG" "✓ $step"
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

# Now that we know the distribution, set the programs.yaml path
PROGRAMS_YAML="$CONFIGS_DIR/$DISTRO_ID/programs.yaml"

# Bootstrap UI tools
bootstrap_tools

# 3. Welcome & Resume Check
clear
gum style --border double --margin "1 2" --padding "1 4" --foreground "$GUM_FG" --border-foreground "$GUM_FG" --bold "LinuxInstaller: Unified Setup" "Detected System: $PRETTY_NAME" "Detected DE: ${XDG_CURRENT_DESKTOP:-None}"

# Check for previous state (Resume capability)
if [ "$DRY_RUN" = false ]; then
    show_resume_menu
else
    log_warn "Dry-Run Mode Active: No changes will be applied."
fi

# 4. Mode Selection
# Only ask if we are not resuming or if mode isn't set in state
if ! is_step_complete "setup_mode"; then
    show_menu
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

# Step: Pacman Configuration (Arch Linux only)
if [ "$DISTRO_ID" == "arch" ] && ! is_step_complete "pacman_config"; then
    step "Configuring Pacman Optimizations"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would configure pacman optimizations (parallel downloads, color, ILoveCandy)"
    else
        # Function to install speedtest-cli silently if not available
        install_speedtest_cli() {
            if ! command -v speedtest-cli >/dev/null 2>&1; then
                log_info "Installing speedtest-cli for network speed detection..."
                if sudo pacman -S --noconfirm --needed speedtest-cli >/dev/null 2>&1; then
                    log_success "speedtest-cli installed successfully"
                    return 0
                else
                    log_warning "Failed to install speedtest-cli - will skip network speed test"
                    return 1
                fi
            fi
            return 0
        }

        # Function to detect network speed and optimize downloads
        detect_network_speed() {
            step "Testing network speed and optimizing download settings"

            # Install speedtest-cli if not available
            if ! install_speedtest_cli; then
                log_warning "speedtest-cli not available - skipping network speed test"
                return
            fi

            log_info "Testing internet speed (this may take a moment)..."

            # Run speedtest and capture download speed (with 30s timeout)
            local speed_test_output=$(timeout 30s speedtest-cli --simple 2>/dev/null)

            if [ $? -eq 0 ] && [ -n "$speed_test_output" ]; then
                local download_speed=$(echo "$speed_test_output" | grep "Download:" | awk '{print $2}')

                if [ -n "$download_speed" ]; then
                    log_success "Download speed: ${download_speed} Mbit/s"

                    # Convert to integer for comparison
                    local speed_int=$(echo "$download_speed" | cut -d. -f1)

                    # Adjust parallel downloads based on speed
                    if [ "$speed_int" -lt 5 ]; then
                        log_warning "Slow connection detected (< 5 Mbit/s)"
                        log_info "Reducing parallel downloads to 3 for stability"
                        log_info "Installation will take longer - consider using ethernet"
                        export PACMAN_PARALLEL=3
                    elif [ "$speed_int" -lt 25 ]; then
                        log_info "Moderate connection speed (5-25 Mbit/s)"
                        log_info "Using standard parallel downloads (10)"
                        export PACMAN_PARALLEL=10
                    elif [ "$speed_int" -lt 100 ]; then
                        log_success "Good connection speed (25-100 Mbit/s)"
                        log_info "Using standard parallel downloads (10)"
                        export PACMAN_PARALLEL=10
                    else
                        log_success "Excellent connection speed (100+ Mbit/s)"
                        log_info "Increasing parallel downloads to 15 for faster installation"
                        export PACMAN_PARALLEL=15
                    fi
                else
                    log_warning "Could not parse speed test results"
                    export PACMAN_PARALLEL=10
                fi
            else
                log_warning "Speed test failed - using default settings"
                export PACMAN_PARALLEL=10
            fi
        }

        configure_pacman() {
            step "Configuring pacman optimizations"

            # Use network-speed-based parallel downloads value (default 10 if not set)
            local parallel_downloads="${PACMAN_PARALLEL:-10}"

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
        detect_network_speed
        configure_pacman
    fi

    mark_step_complete "pacman_config"
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

# Step: Run Gaming Configuration (if applicable)
if ! is_step_complete "gaming_config" && [ "$INSTALL_MODE" != "server" ]; then
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

# 6. Finalization
step "Finalizing Installation"


if [ "$DRY_RUN" = true ]; then
    gum style --margin "0 2" --foreground "$GUM_FG" --bold "Dry-Run Complete. No changes were made."
else
    gum format --theme=dark --foreground "$GUM_FG" "## Installation Complete!" "Your system is ready. Please reboot to ensure all changes take effect."
    prompt_reboot
fi
