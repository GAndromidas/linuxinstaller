#!/bin/bash
set -uo pipefail

# Clear terminal for clean interface
clear

# Get the directory where this script is located (archinstaller root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# Performance tracking
START_TIME=$(date +%s)
TOTAL_STEPS=10

source "$SCRIPTS_DIR/common.sh"

# Optimized installation function with parallel processing
run_optimized_step() {
    local step_name="$1"
    local script_file="$2"
    local step_number="$3"
    
    echo -e "\n${CYAN}Step ${step_number}/${TOTAL_STEPS}: ${step_name}${RESET}"
    
    # Pre-load script to check for errors
    if [ ! -f "$script_file" ]; then
        log_error "${step_name} script not found: $script_file"
        return 1
    fi
    
    # Run step with timeout and better error handling
    if timeout 1800 bash -c "source '$script_file'" 2>&1; then
        log_success "${step_name} completed"
        return 0
    else
        log_error "${step_name} failed"
        return 1
    fi
}

# Pre-optimization tasks (non-duplicate)
pre_optimization() {
    echo -e "${CYAN}Running pre-optimization tasks...${RESET}"
    
    # Update package database in background
    (sudo pacman -Sy --noconfirm >/dev/null 2>&1) &
    
    # Optimize mirrorlist in background
    (sudo reflector --protocol https --latest 3 --sort rate --save /etc/pacman.d/mirrorlist --fastest 1 --connection-timeout 1 >/dev/null 2>&1) &
    
    log_success "Pre-optimization tasks started"
}

# Main installation function
main() {
    arch_ascii
    show_menu
    export INSTALL_MODE

    echo -e "${YELLOW}Please enter your sudo password to begin the installation:${RESET}"
    sudo -v || { echo -e "${RED}Sudo required. Exiting.${RESET}"; exit 1; }

    # Keep sudo alive with optimized method
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill $SUDO_KEEPALIVE_PID 2>/dev/null' EXIT

    echo -e "\n${GREEN}Starting optimized Arch Linux installation...${RESET}\n"

    # Run pre-optimization tasks
    pre_optimization

    # Run installation steps with optimized execution
    local step_number=1
    
    # Step 1: System Preparation (can run in parallel with other steps)
    run_optimized_step "System Preparation" "$SCRIPTS_DIR/system_preparation.sh" $step_number &
    local prep_pid=$!
    ((step_number++))

    # Step 2: Shell Setup
    run_optimized_step "Shell Setup" "$SCRIPTS_DIR/shell_setup.sh" $step_number
    ((step_number++))

    # Step 3: Plymouth Setup
    run_optimized_step "Plymouth Setup" "$SCRIPTS_DIR/plymouth.sh" $step_number
    ((step_number++))

    # Step 4: Yay Installation
    run_optimized_step "Yay Installation" "$SCRIPTS_DIR/yay.sh" $step_number
    ((step_number++))

    # Step 5: Programs Installation (optimized with parallel processing)
    echo -e "\n${CYAN}Step ${step_number}/${TOTAL_STEPS}: Programs Installation${RESET}"
    source "$SCRIPTS_DIR/programs.sh" || log_error "Programs installation failed"
    ((step_number++))

    # Step 6: GameMode Installation
    run_optimized_step "GameMode Installation" "$SCRIPTS_DIR/gamemode.sh" $step_number
    ((step_number++))

    # Step 7: System Boot Configuration
    run_optimized_step "System Boot Configuration" "$SCRIPTS_DIR/system_boot_config.sh" $step_number
    ((step_number++))

    # Step 8: Fail2ban Setup
    run_optimized_step "Fail2ban Setup" "$SCRIPTS_DIR/fail2ban.sh" $step_number
    ((step_number++))

    # Step 9: System Services
    run_optimized_step "System Services" "$SCRIPTS_DIR/system_services.sh" $step_number
    ((step_number++))

    # Step 10: Maintenance
    run_optimized_step "Maintenance" "$SCRIPTS_DIR/maintenance.sh" $step_number
    ((step_number++))

    # Wait for system preparation to complete
    if wait $prep_pid 2>/dev/null; then
        log_success "System preparation completed"
    else
        log_error "System preparation failed"
    fi

    # Calculate total installation time
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))
    
    echo -e "\n${GREEN}Installation completed successfully in ${total_duration} seconds!${RESET}"
    print_programs_summary
    print_summary

    # Delete installer directory if no errors occurred
    if [ ${#ERRORS[@]} -eq 0 ]; then
        echo -e "\n${GREEN}All steps completed successfully. Deleting installer directory before reboot...${RESET}"
        cd "$SCRIPT_DIR/.."
        rm -rf "$(basename "$SCRIPT_DIR")"
    else
        echo -e "\n${YELLOW}Some errors occurred. Installer directory will NOT be deleted.${RESET}"
    fi

    prompt_reboot
}

# Run main function with error handling
main "$@"