#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
# distro_check.sh should have been sourced by install.sh, but for safety in standalone runs:
if [ -z "${DISTRO_ID:-}" ]; then
    if [ -f "$SCRIPT_DIR/distro_check.sh" ]; then
        source "$SCRIPT_DIR/distro_check.sh"
        detect_distro
        define_common_packages
    fi
fi

check_prerequisites() {
  step "Checking system prerequisites"
  if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script as root. Please run as a regular user with sudo privileges."
    return 1
  fi

  # Basic internet check
  if ! ping -c 1 -W 5 google.com &>/dev/null; then
      log_error "No internet connection detected."
      return 1
  fi

  log_success "Prerequisites OK."
}

setup_extra_repos() {
    # Fedora: Enable RPMFusion
    if [ "$DISTRO_ID" == "fedora" ]; then
        step "Enabling RPMFusion Repositories"

        # Check if enabled
        if ! dnf repolist | grep -q rpmfusion-free; then
            log_info "Installing RPMFusion Free & Non-Free..."
            sudo dnf install -y \
                https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
                https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
            log_success "RPMFusion enabled."
        else
            log_info "RPMFusion already enabled."
        fi

        # Enable Codecs (often needed)
        # sudo dnf groupupdate -y core
        # sudo dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
        # sudo dnf groupupdate -y sound-and-video
    fi

    # Debian/Ubuntu: Ensure contrib non-free (usually handled by user, but we can try)
    if [ "$DISTRO_ID" == "debian" ]; then
        # Check /etc/apt/sources.list for non-free-firmware (Bookworm+)
        # This is invasive to edit sources.list blindly. Skipping for safety unless requested.
        :
    fi
}

configure_package_manager() {
    step "Configuring package manager"

    # Run repo setup first
    setup_extra_repos

    if [ "$DISTRO_ID" == "arch" ]; then
        # Arch specific pacman configuration
        if [ -f /etc/pacman.conf ]; then
        local parallel_downloads=10
        if grep -q "^#ParallelDownloads" /etc/pacman.conf; then
            sudo sed -i "s/^#ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
        elif grep -q "^ParallelDownloads" /etc/pacman.conf; then
            sudo sed -i "s/^ParallelDownloads.*/ParallelDownloads = $parallel_downloads/" /etc/pacman.conf
        else
            sudo sed -i "/^\[options\]/a ParallelDownloads = $parallel_downloads" /etc/pacman.conf
        fi

        if grep -q "^#Color" /etc/pacman.conf; then
            sudo sed -i 's/^#Color/Color/' /etc/pacman.conf
            fi
        fi

        # Initialize keyring if needed
        if [ -d /etc/pacman.d ] && [ ! -d /etc/pacman.d/gnupg ] && command -v pacman-key >/dev/null; then
             sudo pacman-key --init 2>/dev/null || true
             sudo pacman-key --populate archlinux 2>/dev/null || true
        fi
    elif [ "$DISTRO_ID" == "fedora" ]; then
        # Fedora optimization
        log_info "Optimizing DNF configuration..."

        # Configure DNF for speed and usability
        for opt in "max_parallel_downloads=10" "fastestmirror=True" "defaultyes=True"; do
            key=$(echo "$opt" | cut -d= -f1)
            if grep -q "^$key" /etc/dnf/dnf.conf; then
                sudo sed -i "s/^$key.*/$opt/" /etc/dnf/dnf.conf
            else
                echo "$opt" | sudo tee -a /etc/dnf/dnf.conf >/dev/null
            fi
        done
        log_success "DNF configuration updated (parallel downloads, fastest mirror, default yes)"
    fi
}

update_system() {
    step "Updating System"
    if ! eval "$PKG_UPDATE"; then
        log_error "System update failed."
        return 1
    fi
    log_success "System updated."
}

set_sudo_pwfeedback() {
  step "Enabling sudo password feedback (asterisks)"

  # Check if pwfeedback is already enabled
  if sudo grep -q '^Defaults.*pwfeedback' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
    log_info "sudo password feedback already enabled. Skipping."
    return 0
  fi

  # Enable password feedback (asterisks when typing password)
  if echo 'Defaults env_reset,pwfeedback' | sudo EDITOR='tee -a' visudo >/dev/null 2>&1; then
    log_success "sudo password feedback enabled (asterisks will show when typing password)"
  else
    log_warning "Failed to enable sudo password feedback. This is not critical."
  fi
}

detect_and_install_solaar() {
  step "Detecting Logitech mouse and installing Solaar"

  # Check if lsusb is available, install usbutils if needed
  if ! command -v lsusb >/dev/null 2>&1; then
    log_info "lsusb not available. Installing usbutils to detect Logitech devices..."
    install_packages_quietly usbutils
    # Wait a moment for usbutils to be available
    sleep 1
  fi

  # Detect Logitech devices (vendor ID 046d)
  # Logitech vendor ID is 046d, we check for any Logitech USB device
  local logitech_detected=false

  # Method 1: Check via lsusb
  if command -v lsusb >/dev/null 2>&1; then
    # Check for Logitech vendor ID (046d) in lsusb output
    if lsusb 2>/dev/null | grep -qiE "046d|Logitech"; then
      logitech_detected=true
      log_success "Logitech device detected via lsusb"
    fi
  fi

  # Method 2: Check /sys/bus/usb/devices for Logitech devices (vendor ID 046d)
  if [ "$logitech_detected" = false ] && [ -d /sys/bus/usb/devices ]; then
    for device_dir in /sys/bus/usb/devices/*/; do
      if [ -f "${device_dir}idVendor" ]; then
        local vendor_id=$(cat "${device_dir}idVendor" 2>/dev/null | tr '[:upper:]' '[:lower:]')
        # Remove leading zeros and compare (046d = 0x046d)
        if [ "$vendor_id" = "046d" ] || [ "$vendor_id" = "0046d" ]; then
          logitech_detected=true
          log_success "Logitech device detected via sysfs (vendor ID: $vendor_id)"
          break
        fi
      fi
    done
  fi

  # Method 3: Check dmesg for Logitech devices (fallback)
  if [ "$logitech_detected" = false ] && dmesg 2>/dev/null | grep -qi "logitech"; then
    logitech_detected=true
    log_success "Logitech device detected via dmesg"
  fi

  if [ "$logitech_detected" = true ]; then
    log_info "Installing Solaar for Logitech device management..."

    # Install solaar based on distro
    if [ "$DISTRO_ID" == "arch" ]; then
      # Solaar is available in AUR for Arch
      if command -v yay >/dev/null 2>&1; then
        if install_aur_quietly solaar; then
          log_success "Solaar installed successfully (AUR)"
        else
          log_warning "Failed to install Solaar from AUR. You can install it manually: yay -S solaar"
        fi
      else
        log_warning "AUR helper (yay) not found. Cannot install Solaar automatically."
        log_info "Please install yay first, then run: yay -S solaar"
      fi
    elif [ "$DISTRO_ID" == "fedora" ]; then
      # Solaar is in Fedora repos
      if install_packages_quietly solaar; then
        log_success "Solaar installed successfully"
      else
        log_warning "Failed to install Solaar. You can try manually: sudo dnf install solaar"
      fi
    elif [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
      # Solaar is in Debian/Ubuntu repos
      if install_packages_quietly solaar; then
        log_success "Solaar installed successfully"
      else
        log_warning "Failed to install Solaar. You can try manually: sudo apt install solaar"
      fi
    else
      log_warning "Unknown distribution. Cannot install Solaar automatically."
      log_info "Please install Solaar manually for your distribution."
    fi
  else
    log_info "No Logitech mouse detected. Skipping Solaar installation."
  fi
}

install_zsh_plugins() {
  # Verify zsh plugins are installed from package managers
  # They should already be installed via install_packages_quietly, but verify
  local zsh_plugins_dir="/usr/share/zsh/plugins"
  local autosuggest_found=false
  local highlight_found=false

  # Check for zsh-autosuggestions
  if [[ -f "$zsh_plugins_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] || \
     [[ -f "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    autosuggest_found=true
  fi

  # Check for zsh-syntax-highlighting
  if [[ -f "$zsh_plugins_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] || \
     [[ -f "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    highlight_found=true
  fi

  if [ "$autosuggest_found" = false ]; then
    log_warning "zsh-autosuggestions not found. Please install via package manager."
  fi

  if [ "$highlight_found" = false ]; then
    log_warning "zsh-syntax-highlighting not found. Please install via package manager."
  fi
}


install_all_packages() {
    step "Installing Base Packages"

    # Filter helper utils if server
    local packages_to_install=("${HELPER_UTILS[@]}")

    if [[ "${INSTALL_MODE:-}" == "server" ]]; then
        ui_info "Server mode: Filtering packages..."
        local server_filtered_packages=()
        for pkg in "${packages_to_install[@]}"; do
             # Simple filter: remove plymouth and bluez related
             if [[ "$pkg" != *"bluez"* && "$pkg" != "plymouth" ]]; then
                server_filtered_packages+=("$pkg")
             fi
        done
        packages_to_install=("${server_filtered_packages[@]}")
    fi

    # Install ZSH and friends
    packages_to_install+=("zsh")

    # Install zsh plugins and starship from package managers (all distros have them)
    if [ "$DISTRO_ID" == "arch" ]; then
        packages_to_install+=("zsh-autosuggestions" "zsh-syntax-highlighting" "starship" "zram-generator")
    elif [ "$DISTRO_ID" == "fedora" ]; then
        packages_to_install+=("zsh-autosuggestions" "zsh-syntax-highlighting" "starship" "zram-generator")
    elif [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
        packages_to_install+=("zsh-autosuggestions" "zsh-syntax-highlighting" "starship")
    fi

    # Generic install loop
    install_packages_quietly "${packages_to_install[@]}"

    # Ensure zsh plugins are installed (manual install if not in repos)
    install_zsh_plugins

    # Verify starship installation (should be installed via package manager above)
         if ! command -v starship >/dev/null; then
        log_warning "Starship not found after package installation. This may indicate a package manager issue."
    fi
}

generate_locales() {
  step "Configuring system locales"

  # Country code to locale mapping (ISO 3166-1 alpha-2 to locale codes)
  declare -A country_to_locale=(
    ["GR"]="el_GR.UTF-8"
    ["US"]="en_US.UTF-8"
    ["GB"]="en_GB.UTF-8"
    ["DE"]="de_DE.UTF-8"
    ["FR"]="fr_FR.UTF-8"
    ["ES"]="es_ES.UTF-8"
    ["IT"]="it_IT.UTF-8"
    ["PT"]="pt_PT.UTF-8"
    ["NL"]="nl_NL.UTF-8"
    ["BE"]="nl_BE.UTF-8"
    ["PL"]="pl_PL.UTF-8"
    ["RU"]="ru_RU.UTF-8"
    ["CN"]="zh_CN.UTF-8"
    ["JP"]="ja_JP.UTF-8"
    ["KR"]="ko_KR.UTF-8"
    ["BR"]="pt_BR.UTF-8"
    ["MX"]="es_MX.UTF-8"
    ["CA"]="en_CA.UTF-8"
    ["AU"]="en_AU.UTF-8"
    ["TR"]="tr_TR.UTF-8"
    ["SE"]="sv_SE.UTF-8"
    ["NO"]="nb_NO.UTF-8"
    ["DK"]="da_DK.UTF-8"
    ["FI"]="fi_FI.UTF-8"
    ["CZ"]="cs_CZ.UTF-8"
    ["HU"]="hu_HU.UTF-8"
    ["RO"]="ro_RO.UTF-8"
    ["BG"]="bg_BG.UTF-8"
    ["HR"]="hr_HR.UTF-8"
    ["SI"]="sl_SI.UTF-8"
    ["SK"]="sk_SK.UTF-8"
    ["EE"]="et_EE.UTF-8"
    ["LV"]="lv_LV.UTF-8"
    ["LT"]="lt_LT.UTF-8"
    ["IE"]="en_IE.UTF-8"
    ["CH"]="de_CH.UTF-8"
    ["AT"]="de_AT.UTF-8"
    ["NZ"]="en_NZ.UTF-8"
    ["ZA"]="en_ZA.UTF-8"
    ["IN"]="en_IN.UTF-8"
    ["SG"]="en_SG.UTF-8"
    ["MY"]="ms_MY.UTF-8"
    ["TH"]="th_TH.UTF-8"
    ["VN"]="vi_VN.UTF-8"
    ["ID"]="id_ID.UTF-8"
    ["PH"]="en_PH.UTF-8"
    ["AR"]="es_AR.UTF-8"
    ["CL"]="es_CL.UTF-8"
    ["CO"]="es_CO.UTF-8"
    ["PE"]="es_PE.UTF-8"
    ["VE"]="es_VE.UTF-8"
    ["IL"]="he_IL.UTF-8"
    ["AE"]="ar_AE.UTF-8"
    ["SA"]="ar_SA.UTF-8"
    ["EG"]="ar_EG.UTF-8"
  )

  local country_code=""
  local detected_locale=""

  # Try to detect country code via IP geolocation
  log_info "Detecting country for locale configuration..."

  if command -v curl >/dev/null 2>&1; then
    # Try multiple services for reliability
    country_code=$(curl -s --connect-timeout 5 --max-time 10 https://ifconfig.co/country-iso 2>/dev/null | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')

    # Fallback services
    if [[ -z "$country_code" || ${#country_code} -ne 2 ]]; then
      country_code=$(curl -s --connect-timeout 5 --max-time 10 "http://ip-api.com/line/?fields=countryCode" 2>/dev/null | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
    fi

    if [[ -z "$country_code" || ${#country_code} -ne 2 ]]; then
      country_code=$(curl -s --connect-timeout 5 --max-time 10 "https://ipapi.co/country_code/" 2>/dev/null | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
    fi
  fi

  # If country detection failed, try system timezone as fallback
  if [[ -z "$country_code" || ${#country_code} -ne 2 ]]; then
    # Try /etc/timezone first
    if [ -f /etc/timezone ]; then
      local tz=$(cat /etc/timezone 2>/dev/null)
      # Extract country code from timezone (e.g., Europe/Athens -> GR)
      case "$tz" in
        *Athens|*Istanbul) country_code="GR" ;;
        *Berlin|*Frankfurt) country_code="DE" ;;
        *Paris) country_code="FR" ;;
        *Madrid) country_code="ES" ;;
        *Rome) country_code="IT" ;;
        *London) country_code="GB" ;;
        *Lisbon) country_code="PT" ;;
        *Amsterdam) country_code="NL" ;;
        *Warsaw) country_code="PL" ;;
        *Moscow) country_code="RU" ;;
        *Tokyo) country_code="JP" ;;
        *Beijing|*Shanghai) country_code="CN" ;;
        *Seoul) country_code="KR" ;;
        *Sao_Paulo|*Rio) country_code="BR" ;;
        *Mexico_City) country_code="MX" ;;
        *Toronto|*Vancouver) country_code="CA" ;;
        *Sydney|*Melbourne) country_code="AU" ;;
        *Stockholm) country_code="SE" ;;
        *Oslo) country_code="NO" ;;
        *Copenhagen) country_code="DK" ;;
        *Helsinki) country_code="FI" ;;
        *Prague) country_code="CZ" ;;
        *Budapest) country_code="HU" ;;
        *Bucharest) country_code="RO" ;;
        *Sofia) country_code="BG" ;;
        *Zagreb) country_code="HR" ;;
        *Ljubljana) country_code="SI" ;;
        *Bratislava) country_code="SK" ;;
        *Tallinn) country_code="EE" ;;
        *Riga) country_code="LV" ;;
        *Vilnius) country_code="LT" ;;
        *Dublin) country_code="IE" ;;
        *Zurich) country_code="CH" ;;
        *Vienna) country_code="AT" ;;
        *Auckland|*Wellington) country_code="NZ" ;;
        *Johannesburg|*Cape_Town) country_code="ZA" ;;
        *Mumbai|*Delhi|*Bangalore) country_code="IN" ;;
        *Singapore) country_code="SG" ;;
        *Kuala_Lumpur) country_code="MY" ;;
        *Bangkok) country_code="TH" ;;
        *Hanoi|*Ho_Chi_Minh) country_code="VN" ;;
        *Jakarta) country_code="ID" ;;
        *Manila) country_code="PH" ;;
        *Buenos_Aires) country_code="AR" ;;
        *Santiago) country_code="CL" ;;
        *Bogota) country_code="CO" ;;
        *Lima) country_code="PE" ;;
        *Caracas) country_code="VE" ;;
        *Jerusalem|*Tel_Aviv) country_code="IL" ;;
        *Dubai|*Abu_Dhabi) country_code="AE" ;;
        *Riyadh) country_code="SA" ;;
        *Cairo) country_code="EG" ;;
      esac
    fi

    # Also try timedatectl if available (systemd)
    if [[ -z "$country_code" || ${#country_code} -ne 2 ]]; then
      if command -v timedatectl >/dev/null 2>&1; then
        local tz=$(timedatectl show --property=Timezone --value 2>/dev/null)
        case "$tz" in
          *Athens|*Istanbul) country_code="GR" ;;
          *Berlin|*Frankfurt) country_code="DE" ;;
          *Paris) country_code="FR" ;;
          *Madrid) country_code="ES" ;;
          *Rome) country_code="IT" ;;
          *London) country_code="GB" ;;
          *Lisbon) country_code="PT" ;;
          *Amsterdam) country_code="NL" ;;
          *Warsaw) country_code="PL" ;;
          *Moscow) country_code="RU" ;;
          *Tokyo) country_code="JP" ;;
          *Beijing|*Shanghai) country_code="CN" ;;
          *Seoul) country_code="KR" ;;
          *Sao_Paulo|*Rio) country_code="BR" ;;
          *Mexico_City) country_code="MX" ;;
          *Toronto|*Vancouver) country_code="CA" ;;
          *Sydney|*Melbourne) country_code="AU" ;;
          *Stockholm) country_code="SE" ;;
          *Oslo) country_code="NO" ;;
          *Copenhagen) country_code="DK" ;;
          *Helsinki) country_code="FI" ;;
          *Prague) country_code="CZ" ;;
          *Budapest) country_code="HU" ;;
          *Bucharest) country_code="RO" ;;
          *Sofia) country_code="BG" ;;
          *Zagreb) country_code="HR" ;;
          *Ljubljana) country_code="SI" ;;
          *Bratislava) country_code="SK" ;;
          *Tallinn) country_code="EE" ;;
          *Riga) country_code="LV" ;;
          *Vilnius) country_code="LT" ;;
          *Dublin) country_code="IE" ;;
          *Zurich) country_code="CH" ;;
          *Vienna) country_code="AT" ;;
          *Auckland|*Wellington) country_code="NZ" ;;
          *Johannesburg|*Cape_Town) country_code="ZA" ;;
          *Mumbai|*Delhi|*Bangalore) country_code="IN" ;;
          *Singapore) country_code="SG" ;;
          *Kuala_Lumpur) country_code="MY" ;;
          *Bangkok) country_code="TH" ;;
          *Hanoi|*Ho_Chi_Minh) country_code="VN" ;;
          *Jakarta) country_code="ID" ;;
          *Manila) country_code="PH" ;;
          *Buenos_Aires) country_code="AR" ;;
          *Santiago) country_code="CL" ;;
          *Bogota) country_code="CO" ;;
          *Lima) country_code="PE" ;;
          *Caracas) country_code="VE" ;;
          *Jerusalem|*Tel_Aviv) country_code="IL" ;;
          *Dubai|*Abu_Dhabi) country_code="AE" ;;
          *Riyadh) country_code="SA" ;;
          *Cairo) country_code="EG" ;;
        esac
      fi
    fi
  fi

  # Special case: If all detection methods failed, default to GR for Greece (user preference)
  # This ensures GR locale is always available when running in Greece
  if [[ -z "$country_code" || ${#country_code} -ne 2 ]]; then
    log_info "Country detection failed. Checking if Greek locale is available..."
    if [ -f /etc/locale.gen ] && grep -q "^#.*el_GR\.UTF-8" /etc/locale.gen; then
      country_code="GR"
      detected_locale="el_GR.UTF-8"
      log_info "Found Greek locale in system. Enabling GR locale as fallback."
    fi
  fi

  # Always enable en_US.UTF-8 (US locale) as default/fallback
  if [ "$DISTRO_ID" == "arch" ]; then
    # Arch uses locale.gen
    if [ -f /etc/locale.gen ]; then
      if grep -q "^#en_US.UTF-8" /etc/locale.gen; then
        sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        log_success "Enabled en_US.UTF-8 locale (US/English)"
      elif ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
        echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
        log_success "Added en_US.UTF-8 locale (US/English)"
      fi

      # Enable local country locale if detected
      if [[ -n "$country_code" && ${#country_code} -eq 2 ]]; then
        detected_locale="${country_to_locale[$country_code]}"

        if [ -z "$detected_locale" ]; then
          # Try to find locale by pattern matching
          detected_locale=$(grep "^#.*_${country_code}\.UTF-8" /etc/locale.gen | head -n 1 | awk '{print $1}' | sed 's/^#//')
        fi

        if [ -n "$detected_locale" ]; then
          if grep -q "^#${detected_locale}" /etc/locale.gen; then
            sudo sed -i "s/^#${detected_locale}/${detected_locale}/" /etc/locale.gen
            log_success "Enabled ${detected_locale} locale (detected country: $country_code)"
          elif ! grep -q "^${detected_locale}" /etc/locale.gen; then
            # Try to add it if it's a standard format
            if [[ "$detected_locale" =~ ^[a-z]{2}_[A-Z]{2}\.UTF-8$ ]]; then
              echo "${detected_locale} UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
              log_success "Added ${detected_locale} locale (detected country: $country_code)"
            fi
          fi
        else
          log_info "No locale mapping found for country code: $country_code"
        fi
      else
        log_warning "Could not detect country. Only en_US.UTF-8 will be enabled."
      fi

      # Regenerate locales
      if command -v locale-gen >/dev/null 2>&1; then
        run_step "Regenerating locales" sudo locale-gen
      else
        log_warning "locale-gen not found. Locales may need manual generation."
      fi
    fi
  elif [ "$DISTRO_ID" == "fedora" ]; then
    # Fedora uses locale.gen (if available) and localectl
    if [ -f /etc/locale.gen ]; then
      # Enable en_US.UTF-8 in locale.gen
      if grep -q "^#en_US.UTF-8" /etc/locale.gen; then
        sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        log_success "Enabled en_US.UTF-8 locale (US/English)"
      elif ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
        echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
        log_success "Added en_US.UTF-8 locale (US/English)"
      fi

      # Enable local country locale if detected
      if [[ -n "$country_code" && ${#country_code} -eq 2 ]]; then
        if [ -z "$detected_locale" ]; then
          detected_locale="${country_to_locale[$country_code]}"
        fi

        if [ -z "$detected_locale" ]; then
          # Try to find locale by pattern matching
          detected_locale=$(grep "^#.*_${country_code}\.UTF-8" /etc/locale.gen | head -n 1 | awk '{print $1}' | sed 's/^#//')
        fi

        if [ -n "$detected_locale" ]; then
          if grep -q "^#${detected_locale}" /etc/locale.gen; then
            sudo sed -i "s/^#${detected_locale}/${detected_locale}/" /etc/locale.gen
            log_success "Enabled ${detected_locale} locale (detected country: $country_code)"
          elif ! grep -q "^${detected_locale}" /etc/locale.gen; then
            if [[ "$detected_locale" =~ ^[a-z]{2}_[A-Z]{2}\.UTF-8$ ]]; then
              echo "${detected_locale} UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
              log_success "Added ${detected_locale} locale (detected country: $country_code)"
            fi
          fi
        fi
      fi

      # Regenerate locales
      if command -v locale-gen >/dev/null 2>&1; then
        run_step "Regenerating locales" sudo locale-gen
      fi
    fi

    # Also use localectl for system-wide locale setting
    if command -v localectl >/dev/null 2>&1; then
      # Set to detected locale if available, otherwise use en_US.UTF-8
      if [[ -n "$detected_locale" && -n "$country_code" ]]; then
        sudo localectl set-locale "LANG=${detected_locale}" 2>/dev/null || \
        sudo localectl set-locale "LANG=en_US.UTF-8" 2>/dev/null || true
        log_success "Set system locale to ${detected_locale}"
      else
        sudo localectl set-locale "LANG=en_US.UTF-8" 2>/dev/null || true
        log_success "Set system locale to en_US.UTF-8"
      fi
    fi
  elif [ "$DISTRO_ID" == "debian" ] || [ "$DISTRO_ID" == "ubuntu" ]; then
    # Debian/Ubuntu use locale.gen and dpkg-reconfigure
    if [ -f /etc/locale.gen ]; then
      # Enable en_US.UTF-8
      if grep -q "^#en_US.UTF-8" /etc/locale.gen; then
        sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        log_success "Enabled en_US.UTF-8 locale (US/English)"
      elif ! grep -q "^en_US.UTF-8" /etc/locale.gen; then
        echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
        log_success "Added en_US.UTF-8 locale (US/English)"
      fi

      # Enable local country locale if detected
      if [[ -n "$country_code" && ${#country_code} -eq 2 ]]; then
        detected_locale="${country_to_locale[$country_code]}"

        if [ -z "$detected_locale" ]; then
          # Try to find locale by pattern matching
          detected_locale=$(grep "^#.*_${country_code}\.UTF-8" /etc/locale.gen | head -n 1 | awk '{print $1}' | sed 's/^#//')
        fi

        if [ -n "$detected_locale" ]; then
          if grep -q "^#${detected_locale}" /etc/locale.gen; then
            sudo sed -i "s/^#${detected_locale}/${detected_locale}/" /etc/locale.gen
            log_success "Enabled ${detected_locale} locale (detected country: $country_code)"
          elif ! grep -q "^${detected_locale}" /etc/locale.gen; then
            if [[ "$detected_locale" =~ ^[a-z]{2}_[A-Z]{2}\.UTF-8$ ]]; then
              echo "${detected_locale} UTF-8" | sudo tee -a /etc/locale.gen >/dev/null
              log_success "Added ${detected_locale} locale (detected country: $country_code)"
            fi
          fi
        fi
      fi

      # Regenerate locales
      if command -v locale-gen >/dev/null 2>&1; then
        run_step "Regenerating locales" sudo locale-gen
      elif command -v dpkg-reconfigure >/dev/null 2>&1; then
        run_step "Regenerating locales" sudo dpkg-reconfigure -f noninteractive locales
      else
        log_warning "locale-gen/dpkg-reconfigure not found. Locales may need manual generation."
             fi
         fi
    fi

  if [[ -n "$country_code" && ${#country_code} -eq 2 ]]; then
    log_success "Locale configuration complete: en_US.UTF-8 + ${detected_locale:-local} (Country: $country_code)"
  else
    log_success "Locale configuration complete: en_US.UTF-8 (Country detection failed)"
  fi
}

# Run steps
check_prerequisites
configure_package_manager
update_system
set_sudo_pwfeedback
generate_locales
install_all_packages
detect_and_install_solaar
