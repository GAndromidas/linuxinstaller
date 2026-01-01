# Development Guide

This guide is for developers who want to contribute to LinuxInstaller.

## 🚀 Getting Started

### Prerequisites

- **Git**: Version control system
- **Bash**: Shell scripting knowledge
- **Linux Knowledge**: Understanding of Linux distributions
- **Testing Environment**: VM or container for testing changes

### Development Setup

```bash
# Clone the repository
git clone https://github.com/GAndromidas/linuxinstaller.git
cd linuxinstaller

# Create a feature branch
git checkout -b feature/your-feature-name

# Make your changes
# ... edit files ...

# Test your changes
sudo ./install.sh --dry-run --verbose

# Commit your changes
git add .
git commit -m "Add: brief description of changes"

# Push to your branch
git push origin feature/your-feature-name

# Create a Pull Request
```

## 🏗️ Architecture Overview

### Modular Design

LinuxInstaller uses a modular architecture:

```
linuxinstaller/
├── install.sh              # Main orchestration script
├── scripts/               # Modular components
│   ├── common.sh          # Shared utilities (UI, logging, package management)
│   ├── distro_check.sh    # Distribution detection and capabilities
│   ├── arch_config.sh     # Arch Linux specific configuration
│   ├── fedora_config.sh   # Fedora specific configuration
│   ├── debian_config.sh   # Debian/Ubuntu configuration
│   └── *.sh               # Feature-specific modules
└── configs/               # Distribution-specific configuration files
    └── */                 # Per-distribution configs (.zshrc, starship.toml, etc.)
```

### Key Components

1. **Main Script** (`install.sh`):
   - Command-line argument parsing
   - Installation mode selection
   - Step orchestration
   - Error handling

2. **Common Module** (`scripts/common.sh`):
   - Gum UI wrapper functions
   - Logging utilities
   - Package management abstractions
   - System detection helpers

3. **Distribution Modules** (`scripts/*_config.sh`):
   - Distribution-specific package lists
   - System configuration logic
   - Service management

## 📝 Coding Standards

### Bash Scripting Guidelines

#### File Structure
```bash
#!/bin/bash
set -uo pipefail

# =============================================================================
# Module Name - Brief Description
# =============================================================================
#
# DESCRIPTION:
#   Detailed description of what this module does
#
# USAGE:
#   source this_script.sh
#   function_name arg1 arg2
#
# DEPENDENCIES:
#   - required_module.sh
#   - external_command
#
# AUTHOR: Contributor Name
# =============================================================================

# --- Configuration & Constants ---
# Global constants and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# --- Helper Functions ---
# Private utility functions

# --- Public API Functions ---
# Main functions exposed to other modules

# --- Main Execution (if applicable) ---
# Only if this script can be run directly
```

#### Naming Conventions

```bash
# Functions: snake_case
function install_package() { ... }
function check_dependencies() { ... }

# Variables: UPPERCASE for constants, lowercase for locals
readonly CONFIG_FILE="/etc/linuxinstaller/config"
local temp_file="/tmp/temp"

# Arrays: plural names
local package_list=()
local error_messages=()

# Constants: UPPERCASE with underscores
readonly DEFAULT_TIMEOUT=30
readonly MAX_RETRIES=3
```

#### Error Handling

```bash
# Use set -uo pipefail
set -uo pipefail

# Check command success
if ! command_exists "required_tool"; then
    log_error "required_tool is not installed"
    return 1
fi

# Validate inputs
function validate_package_name() {
    local package="$1"

    if [[ "$package" =~ [^a-zA-Z0-9._+-] ]]; then
        log_error "Invalid package name: $package"
        return 1
    fi
}

# Use return codes consistently
function install_package() {
    # ... installation logic ...

    if [ $? -ne 0 ]; then
        log_error "Failed to install package"
        return 1
    fi

    return 0
}
```

### Documentation Standards

#### Function Documentation

```bash
# Install a package using the system package manager
# This function handles package installation across different distributions
# with proper error handling and logging.
#
# Arguments:
#   $1 - Package name to install
#   $2 - Package type (native, aur, flatpak, snap) - optional, defaults to native
#
# Returns:
#   0 - Success
#   1 - Installation failed
#   2 - Invalid package name
#
# Example:
#   install_pkg "zsh"
#   install_pkg "yay" "aur"
#
install_pkg() {
    local package="$1"
    local pkg_type="${2:-native}"

    # Function implementation...
}
```

#### Module Documentation

Each module should have a header comment explaining:

- Purpose and scope
- Dependencies
- Usage examples
- Important notes or warnings

## 🧪 Testing Guidelines

### Testing Strategy

1. **Unit Tests**: Test individual functions
2. **Integration Tests**: Test module interactions
3. **System Tests**: Full installation testing
4. **Regression Tests**: Ensure existing functionality still works

### Testing Environment

```bash
# Create a test VM or container
# Test on multiple distributions
# Use different installation modes

# Test commands
sudo ./install.sh --dry-run --verbose
sudo ./install.sh --dry-run  # Quick test
```

### Test Cases

#### Critical Test Cases
- [ ] Installation completes successfully on all supported distributions
- [ ] All package types install correctly (native, AUR, Flatpak, Snap)
- [ ] Security configurations are applied correctly
- [ ] Performance optimizations work
- [ ] Desktop environment configurations apply
- [ ] Shell configurations are set up correctly

#### Error Handling Tests
- [ ] Network failures are handled gracefully
- [ ] Package installation failures don't break the entire installation
- [ ] Invalid inputs are rejected with clear error messages
- [ ] System compatibility issues are detected and reported

### Automated Testing

```bash
# Syntax checking
bash -n install.sh
bash -n scripts/*.sh

# ShellCheck linting
shellcheck install.sh
shellcheck scripts/*.sh

# JSON/TOML validation
python3 -c "import json; json.load(open('configs/arch/config.jsonc'))"
python3 -c "import toml; toml.load('configs/arch/starship.toml')"
```

## 🔧 Development Workflow

### Creating a New Feature

1. **Plan the Feature:**
   - Define requirements and scope
   - Identify affected modules
   - Plan testing approach

2. **Create Feature Branch:**
   ```bash
   git checkout -b feature/package-manager-improvements
   ```

3. **Implement Changes:**
   - Follow coding standards
   - Add comprehensive documentation
   - Test thoroughly

4. **Commit Changes:**
   ```bash
   git add .
   git commit -m "feat: improve package manager error handling

   - Add retry logic for failed installations
   - Better error messages for network issues
   - Improved logging for debugging"
   ```

5. **Create Pull Request:**
   - Write clear description
   - Reference related issues
   - Request review from maintainers

### Code Review Process

#### For Contributors
- Ensure all tests pass
- Follow coding standards
- Add documentation
- Test on multiple distributions

#### For Reviewers
- Check code quality and standards
- Verify functionality
- Test edge cases
- Ensure backward compatibility

## 📦 Package Management

### Adding New Packages

#### Native Packages
Add to distribution-specific arrays in config files:

```bash
# scripts/arch_config.sh
ARCH_NATIVE_STANDARD+=(
    "new-package"
    "another-package"
)
```

#### AUR Packages (Arch Only)
```bash
# scripts/arch_config.sh
ARCH_AUR_STANDARD+=(
    "package-from-aur"
)
```

#### Flatpak Packages
```bash
# scripts/fedora_config.sh
FEDORA_FLATPAK_STANDARD+=(
    "org.package.Name"
)
```

### Package Validation

Before adding packages, verify:

```bash
# Check if package exists
pacman -Si package_name    # Arch
apt search package_name    # Ubuntu
dnf search package_name     # Fedora

# Check dependencies
pactree package_name       # Arch
apt depends package_name   # Ubuntu
dnf repoquery --requires package_name  # Fedora
```

## 🔒 Security Considerations

### Input Validation

```bash
# Always validate user inputs
function validate_package_name() {
    local package="$1"

    # Reject dangerous characters
    if [[ "$package" =~ [^a-zA-Z0-9._+-] ]]; then
        log_error "Invalid package name contains special characters: $package"
        return 1
    fi

    # Check for command injection attempts
    if [[ "$package" =~ [\;\|\&\`\$] ]]; then
        log_error "Package name contains dangerous characters: $package"
        return 1
    fi
}
```

### Secure File Operations

```bash
# Use secure temporary directories
local temp_dir
temp_dir=$(mktemp -d) || {
    log_error "Failed to create temporary directory"
    return 1
}

# Secure permissions
chmod 700 "$temp_dir"

# Cleanup on exit
trap 'rm -rf "$temp_dir"' EXIT

# Safe file copying
cp --preserve=mode,ownership "$source" "$destination" || {
    log_error "Failed to copy file: $source -> $destination"
    return 1
}
```

### Privilege Management

```bash
# Use sudo only when necessary
if [ "$EUID" -eq 0 ]; then
    # Already running as root
    install_command="pacman -S --noconfirm"
else
    # Need sudo for system operations
    install_command="sudo pacman -S --noconfirm"
fi

# Validate sudo access
if ! sudo -n true 2>/dev/null; then
    log_error "sudo access required but not available"
    return 1
fi
```

## 🎨 UI/UX Development

### Gum Integration

```bash
# Use consistent styling
function show_menu() {
    gum style --border double --margin "1 2" --padding "1 2" \
             --foreground "$GUM_PRIMARY_FG" --border-foreground "$GUM_BORDER_FG" \
             --bold "LinuxInstaller Menu"
}

# Handle fallbacks gracefully
if supports_gum; then
    # Rich UI
    choice=$(gum choose "${options[@]}")
else
    # Text fallback
    select choice in "${options[@]}"; do
        break
    done
fi
```

### Progress Indicators

```bash
# Use appropriate progress indicators
if supports_gum; then
    gum spin --spinner dot --title "Installing packages..." -- install_packages
else
    echo "Installing packages..."
    install_packages
fi
```

## 🌐 Distribution Support

### Adding New Distributions

1. **Create Distribution Module:**
   ```bash
   # scripts/newdistro_config.sh
   #!/bin/bash
   set -uo pipefail

   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/common.sh"
   source "$SCRIPT_DIR/distro_check.sh"

   # Distribution-specific configuration
   ```

2. **Update Distribution Detection:**
   ```bash
   # scripts/distro_check.sh
   detect_distro() {
       if [ -f /etc/os-release ]; then
           . /etc/os-release
           case "$ID" in
               newdistro)
                   DISTRO_ID="newdistro"
                   PKG_INSTALL="newdistro-pkg-install"
                   ;;
           esac
       fi
   }
   ```

3. **Update Main Script:**
   ```bash
   # install.sh
   case "$DISTRO_ID" in
       "newdistro")
           source "$SCRIPTS_DIR/newdistro_config.sh"
           ;;
   esac
   ```

## 📚 Documentation

### Wiki Maintenance

- Keep wiki pages up to date with code changes
- Add examples for new features
- Update troubleshooting guides
- Maintain cross-references between pages

### Code Documentation

- Document all public functions
- Explain complex algorithms
- Provide usage examples
- Note important caveats or limitations

### Release Notes

When preparing releases:

```markdown
## v1.1.0 - New Features Release

### ✨ New Features
- Added support for new distribution
- New gaming optimizations
- Enhanced security configurations

### 🐛 Bug Fixes
- Fixed package installation on Fedora
- Resolved GPU detection issues
- Improved error handling

### 🔧 Improvements
- Better progress indicators
- Enhanced documentation
- Performance optimizations
```

## 🤝 Contribution Guidelines

### Pull Request Checklist

- [ ] Tests pass on all supported distributions
- [ ] Code follows established patterns and standards
- [ ] Documentation is updated
- [ ] No breaking changes without justification
- [ ] Security implications reviewed
- [ ] Performance impact assessed

### Commit Message Format

```bash
type(scope): description

[optional body]

[optional footer]
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation
- `style`: Code style changes
- `refactor`: Code refactoring
- `test`: Testing
- `chore`: Maintenance

Examples:
```
feat: add support for Fedora 39
fix: resolve NVIDIA driver detection issue
docs: update installation guide for new features
refactor: simplify package installation logic
```

## 📞 Getting Help

### Development Discussions
- **GitHub Discussions**: For development questions and design discussions
- **Issues**: For bug reports and feature requests
- **Code Reviews**: Request reviews on pull requests

### Development Resources
- **Bash Documentation**: [GNU Bash Manual](https://www.gnu.org/software/bash/manual/)
- **ShellCheck**: [Online Linter](https://www.shellcheck.net/)
- **Gum Documentation**: [Charm Documentation](https://github.com/charmbracelet/gum)

---

**Happy contributing! Your improvements help make LinuxInstaller better for everyone. 🚀**</content>
<parameter name="filePath">linuxinstaller/wiki/Development-Guide.md