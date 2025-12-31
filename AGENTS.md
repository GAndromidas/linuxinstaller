# LinuxInstaller Agent Guidelines

## Quick Commands

### Development & Testing
```bash
# Syntax check all scripts
bash -n install.sh scripts/*.sh

# Lint (if shellcheck available)
shellcheck install.sh scripts/*.sh

# Dry run (no changes)
sudo ./install.sh --dry-run

# Test single module
source scripts/common.sh && source scripts/distro_check.sh
source scripts/arch_config.sh && gaming_main_config
```

### Git Operations
```bash
git status --short
git add scripts/*_config.sh
git diff --cached
git rebase -i origin/main  # Clean history before push
```

## Code Style

### File Header
```bash
#!/bin/bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/distro_check.sh"
```

### Imports (Source Order)
1. `common.sh` (utilities, logging, gum)
2. `distro_check.sh` (distro detection)
3. Distros: `arch_config.sh`, `fedora_config.sh`, `debian_config.sh`
4. Features: sourced by `install.sh` orchestration

**Never source feature modules directly** - use `install.sh` flow.

### Naming Conventions
```bash
# Functions: <feature>_<action>()
gaming_main_config()        # Entry point
gaming_install_packages()     # Install
gaming_configure_performance() # Configure

# Utilities: <verb>_noun()
install_pkg(), remove_pkg(), mark_step_complete(), is_step_complete()

# Constants: UPPER_SNAKE_CASE
INSTALL_MODE, INSTALL_GAMING, DISTRO_ID

# Locals: lower_snake_case
local section="$1", local package=""

# Package Arrays: <DISTRO>_<CATEGORY>_<SUBCATEGORY>()
ARCH_GAMING_NATIVE=()
ARCH_NATIVE_STANDARD=()
FEDORA_NATIVE_STANDARD=()
DEBIAN_GAMING_NATIVE=()
```

### Error Handling
```bash
# Always use || true for graceful degradation
command-might-fail || true

# Guarded operations
if [ -n "$package" ]; then
    install_pkg "$package"
fi

# Check return codes
if ! sudo pacman -Sy >/dev/null 2>&1; then
    log_error "Failed to update package database"
fi
```

### Logging
```bash
step()        # Section headers (blue accent)
log_info()    # Informational
log_success()  # Success confirmations (green)
log_warn()     # Warnings (yellow)
log_error()    # Critical errors (red)
```

### Gum Integration
```bash
# Always guard gum calls
if supports_gum; then
    gum style --foreground "$GUM_SUCCESS_FG" "✓ Success"
else
    echo "✓ Success" # Fallback
fi

# Always add || true for graceful failure
gum choose --height 10 ... || true
```

## API Design

### distro_get_packages() API
```bash
# Usage
distro_get_packages <section> <type>

# Examples
distro_get_packages "gaming" "native"
distro_get_packages "kde" "flatpak"

# Returns: newline-separated package list
mapfile -t packages < <(distro_get_packages ... 2>/dev/null || true)
```

### Return Codes
- 0 = Success
- 1 = Warning/non-critical failure (continue execution)

## State Management
```bash
# Location: ~/.linuxinstaller-state
mark_step_complete "gaming_config"
is_step_complete "gaming_config"
clear_state
```

## Module Structure (Required)

1. Shebang & setup with `set -uo pipefail`
2. Package arrays (if distro-specific)
3. API function: `distro_get_packages()`
4. Main entry: `<feature>_main_config()`
5. Sub-functions: `<feature>_<action>()`
6. Exports: `export -f` for all public functions

## Common Pitfalls

1. **Hardcoding distro packages** → Use `distro_get_packages()` API
2. **Not exporting functions** → Always `export -f` public functions
3. **Skipping error guards** → Use `|| true` and check return codes
4. **Wrong source order** → Follow `common.sh` → `distro_check.sh` → distro config
5. **Assuming gum exists** → Guard with `if supports_gum`
6. **Not checking DISTRO_ID** → Check `$DISTRO_ID` before distro-specific ops
7. **State file issues** → Use `is_step_complete()` before running steps
8. **Empty arrays** → Check `${#array[@]} -eq 0` before iteration
9. **Missing INSTALL_GAMING checks** → Always verify before gaming config
10. **Not using step() headers** → Use `step()` for major sections

## Commit Guidelines
- Format: `Fix: <desc>`, `Feature: <desc>`, `Refactor: <desc>`
- Focused: One logical change per commit
- Explain "why" not just "what"
- Test: Run `bash -n` before committing

 ## Pre-Push Checklist
 - [ ] All scripts pass `bash -n` syntax check
 - [ ] New functions exported with `export -f`
 - [ ] `distro_get_packages()` API in distro config
 - [ ] INSTALL_GAMING checks in place (if gaming module)
 - [ ] Gum calls guarded with `supports_gum`
 - [ ] Error handling with `|| true` or explicit checks
 - [ ] State management uses `is_step_complete()` / `mark_step_complete()`
 - [ ] Naming: `<feature>_<action>` format
 - [ ] Package arrays: `<DISTRO>_<CATEGORY>` format
 - [ ] Comments explain non-obvious logic
 - [ ] New .sh scripts made executable with `chmod +x`
