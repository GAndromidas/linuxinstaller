#!/bin/bash
# =============================================================================
# Display Module for LinuxInstaller
# Centralized terminal UI functions with theming support
# =============================================================================

# Note: This module assumes common.sh is already sourced

# -----------------------------------------------------------------------------
# THEME CONFIGURATION
# -----------------------------------------------------------------------------
# Default theme (easily configurable)
THEME_NAME="${THEME_NAME:-default}"
THEME_PRIMARY="${THEME_PRIMARY:-cyan}"
THEME_SUCCESS="${THEME_SUCCESS:-green}"
THEME_ERROR="${THEME_ERROR:-red}"
THEME_WARNING="${THEME_WARNING:-yellow}"
THEME_INFO="${THEME_INFO:-blue}"
THEME_BODY="${THEME_BODY:-white}"

# Distro-specific themes and colors (set later when DISTRO_ID is available)
update_distro_theme() {
    if [ -n "${DISTRO_ID:-}" ]; then
        case "$DISTRO_ID" in
            "arch")
                # Arch Linux: Blue theme
                THEME_PRIMARY="blue"
                THEME_PRIMARY_ANSI='\033[0;34m'  # Blue
                GUM_PRIMARY_FG=39      # Blue
                GUM_SUCCESS_FG=48      # Bright green-cyan
                GUM_ERROR_FG=196       # Red
                GUM_WARNING_FG=226     # Yellow
                GUM_INFO_FG=39         # Blue
                GUM_BODY_FG=87         # Light cyan
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[0;33m'
                BLUE='\033[0;34m'
                CYAN='\033[0;34m'      # Blue for accents
                LIGHT_CYAN='\033[1;34m' # Light blue
                ;;
            "fedora")
                # Fedora: Blue theme
                THEME_PRIMARY="blue"
                THEME_PRIMARY_ANSI='\033[0;34m'  # Blue
                GUM_PRIMARY_FG=39      # Blue
                GUM_SUCCESS_FG=48      # Bright green-cyan
                GUM_ERROR_FG=196       # Red
                GUM_WARNING_FG=226     # Yellow
                GUM_INFO_FG=39         # Blue
                GUM_BODY_FG=87         # Light cyan
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[0;33m'
                BLUE='\033[0;34m'
                CYAN='\033[0;34m'      # Blue for accents
                LIGHT_CYAN='\033[1;34m' # Light blue
                ;;
            "debian")
                # Debian: Red theme
                THEME_PRIMARY="red"
                THEME_PRIMARY_ANSI='\033[0;31m'  # Red
                GUM_PRIMARY_FG=196     # Red
                GUM_SUCCESS_FG=48      # Bright green-cyan
                GUM_ERROR_FG=196       # Red
                GUM_WARNING_FG=226     # Yellow
                GUM_INFO_FG=196        # Red
                GUM_BODY_FG=87         # Light cyan
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[0;33m'
                BLUE='\033[0;34m'
                CYAN='\033[0;31m'      # Red for accents
                LIGHT_CYAN='\033[1;31m' # Light red
                ;;
            "ubuntu")
                # Ubuntu: Orange theme
                THEME_PRIMARY="yellow"  # Closest to orange
                THEME_PRIMARY_ANSI='\033[0;33m'  # Yellow/Orange
                GUM_PRIMARY_FG=214     # Orange
                GUM_SUCCESS_FG=48      # Bright green-cyan
                GUM_ERROR_FG=196       # Red
                GUM_WARNING_FG=226     # Yellow
                GUM_INFO_FG=214        # Orange
                GUM_BODY_FG=87         # Light cyan
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[0;33m'
                BLUE='\033[0;34m'
                ORANGE='\033[0;33m'    # Yellow as orange
                CYAN='\033[0;33m'      # Orange for accents
                LIGHT_CYAN='\033[1;33m' # Light orange
                ;;
            *)
                # Default: Cyan theme (original)
                THEME_PRIMARY="cyan"
                THEME_PRIMARY_ANSI='\033[0;36m'  # Cyan
                GUM_PRIMARY_FG="cyan"
                GUM_SUCCESS_FG=48
                GUM_ERROR_FG=196
                GUM_WARNING_FG=226
                GUM_INFO_FG="cyan"
                GUM_BODY_FG=87
                RED='\033[0;31m'
                GREEN='\033[0;32m'
                YELLOW='\033[0;33m'
                BLUE='\033[0;34m'
                CYAN='\033[0;36m'
                LIGHT_CYAN='\033[1;36m'
                ;;
        esac
    fi
}

# -----------------------------------------------------------------------------
# CORE DISPLAY FUNCTIONS
# -----------------------------------------------------------------------------

# Display a step header with icon and consistent formatting
display_step() {
    local icon="${1:-🚀}"
    local title="$2"
    local subtitle="${3:-}"

    if supports_gum; then
        gum style "$icon $title" --foreground "$THEME_PRIMARY" --bold --margin "1 0"
        [ -n "$subtitle" ] && gum style "$subtitle" --foreground "$THEME_BODY" --margin "0 2"
    else
        echo -e "\n[${THEME_PRIMARY_ANSI}$icon${RESET}] $title"
        [ -n "$subtitle" ] && echo "  $subtitle"
    fi
}

# Display progress item with status
display_progress() {
    local status="$1"  # installing|completed|failed|skipped
    local item="$2"
    local details="${3:-}"

    case "$status" in
        "installing")
            echo "  • Installing $item"
            [ -n "$details" ] && echo "    $details"
            ;;
        "completed")
            display_success "✓ $item" "$details"
            ;;
        "failed")
            display_error "✗ $item" "$details"
            ;;
        "skipped")
            display_info "○ $item (skipped)" "$details"
            ;;
    esac
}

# Display success message
display_success() {
    local message="$1"
    local details="${2:-}"

    if supports_gum; then
        gum style "$message" --foreground "$THEME_SUCCESS" --margin "0 2"
        [ -n "$details" ] && gum style "$details" --foreground "$THEME_BODY" --margin "0 4"
    else
        echo -e "${GREEN}✓ $message${RESET}"
        [ -n "$details" ] && echo "  $details"
    fi
}

# Display error message
display_error() {
    local message="$1"
    local details="${2:-}"

    if supports_gum; then
        gum style "$message" --foreground "$THEME_ERROR" --margin "0 2"
        [ -n "$details" ] && gum style "$details" --foreground "$THEME_BODY" --margin "0 4"
    else
        echo -e "${RED}✗ $message${RESET}"
        [ -n "$details" ] && echo "  $details"
    fi
}

# Display warning message
display_warning() {
    local message="$1"
    local details="${2:-}"

    if supports_gum; then
        gum style "$message" --foreground "$THEME_WARNING" --margin "0 2"
        [ -n "$details" ] && gum style "$details" --foreground "$THEME_BODY" --margin "0 4"
    else
        echo -e "${YELLOW}⚠ $message${RESET}"
        [ -n "$details" ] && echo "  $details"
    fi
}

# Display info message
display_info() {
    local message="$1"
    local details="${2:-}"

    if supports_gum; then
        gum style "$message" --foreground "$THEME_INFO" --margin "0 2"
        [ -n "$details" ] && gum style "$details" --foreground "$THEME_BODY" --margin "0 4"
    else
        echo -e "${CYAN}ℹ $message${RESET}"
        [ -n "$details" ] && echo "  $details"
    fi
}

# Display a bordered information box
display_box() {
    local title="$1"
    local content="${2:-}"
    local border_color="${3:-$THEME_INFO}"

    if supports_gum; then
        gum style "$title" --bold --foreground "$border_color" --border rounded --border-foreground "$border_color" --padding "1 2" --margin "1 0"
        [ -n "$content" ] && echo "$content"
    else
        echo -e "\n[${CYAN}$title${RESET}]"
        [ -n "$content" ] && echo "$content"
        echo
    fi
}

# Display a summary panel
display_summary() {
    local title="$1"
    shift
    local items=("$@")

    display_box "$title" "" "$THEME_SUCCESS"
    for item in "${items[@]}"; do
        echo "  $item"
    done
    echo
}

# Enhanced spinner with better visuals
display_spin() {
    local title="$1"
    shift

    if supports_gum; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo -n "$title... "
        "$@" >/dev/null 2>&1
        echo "Done"
    fi
}

# -----------------------------------------------------------------------------
# LEGACY COMPATIBILITY FUNCTIONS
# -----------------------------------------------------------------------------
# These wrap the new functions to maintain backward compatibility

step() {
    display_step "❯" "$1"
}

log_info() {
    display_info "$1"
}

log_success() {
    display_success "$1"
}

log_warn() {
    display_warning "$1"
}

log_error() {
    display_error "$1"
}

# Package installation with clean final summary (no intermediate progress)
install_packages_with_progress() {
    local packages=("$@")
    local installed_packages=()
    local failed_packages=()

    for package in "${packages[@]}"; do
        if [ -n "$package" ]; then
            if install_pkg "$package" >/dev/null 2>&1; then
                installed_packages+=("$package")
            else
                failed_packages+=("$package")
            fi
        fi
    done

    if [ ${#installed_packages[@]} -gt 0 ]; then
        display_success "Successfully installed packages: ${installed_packages[*]}"
    fi
    if [ ${#failed_packages[@]} -gt 0 ]; then
        display_error "Failed packages: ${failed_packages[*]}"
    fi
}

# Functions are available after sourcing this file