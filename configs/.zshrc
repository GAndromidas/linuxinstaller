# =============================================================================
# ZSH Configuration
# =============================================================================

# Initialize completion
autoload -U compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'      # Case insensitive tab completion
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"         # Colored completion (like ls)
zstyle ':completion:*' rehash true                              # Automatically find new executables in path
# Speed up completion
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
compinit
_comp_options+=(globdots)                                       # Include hidden files

# Basic Options
setopt HIST_IGNORE_ALL_DUPS      # Don't record dupes in history
setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks
setopt SHARE_HISTORY             # Share history between sessions
setopt EXTENDED_HISTORY          # Write the history file in the ":start:elapsed;command" format
setopt AUTO_CD                   # cd by typing directory name
setopt CORRECT                   # Spelling correction
setopt INTERACTIVE_COMMENTS      # Allow comments in interactive shell

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# Keybindings (Standard Arch / Linux keys)
bindkey -e                                                      # Emacs key bindings
bindkey '^[[7~' beginning-of-line                               # Home key
bindkey '^[[H' beginning-of-line                                # Home key
bindkey '^[[8~' end-of-line                                     # End key
bindkey '^[[F' end-of-line                                      # End key
bindkey '^[[2~' overwrite-mode                                  # Insert key
bindkey '^[[3~' delete-char                                     # Delete key
bindkey '^[[C'  forward-char                                    # Right key
bindkey '^[[D'  backward-char                                   # Left key
bindkey '^[[5~' history-beginning-search-backward               # Page up key
bindkey '^[[6~' history-beginning-search-forward                # Page down key
# Navigate words with ctrl+arrow keys
bindkey '^[Oc' forward-word                                     # Ctrl+Right
bindkey '^[Od' backward-word                                    # Ctrl+Left
bindkey '^[[1;5D' backward-word                                 # Ctrl+Left
bindkey '^[[1;5C' forward-word                                  # Ctrl+Right
bindkey '^H' backward-kill-word                                 # Ctrl+Backspace
bindkey '^[[Z' undo                                             # Shift+Tab undo

# =============================================================================
# Plugins (Sourced from system locations)
# =============================================================================

# FZF (Fuzzy Finder) - Ctrl+R (History), Ctrl+T (Files), Alt+C (Dirs)
if [ -f /usr/share/fzf/key-bindings.zsh ]; then
    source /usr/share/fzf/key-bindings.zsh
fi
if [ -f /usr/share/fzf/completion.zsh ]; then
    source /usr/share/fzf/completion.zsh
fi

# Autosuggestions
if [ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
fi

# Syntax Highlighting (Must be sourced last)
if [ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# =============================================================================
# Aliases
# =============================================================================

# -----------------------------------------------------------------------------
# System Maintenance
# -----------------------------------------------------------------------------
alias sync='sudo pacman -Syy'                                                      # Sync package databases
alias update='yay -Syyu && sudo flatpak update'                                    # Update all packages (Pacman, AUR, Flatpak)
alias mirror='sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch && sudo pacman -Syy'  # Update mirror list
alias clean='sudo pacman -Sc --noconfirm && yay -Sc --noconfirm && sudo flatpak uninstall --unused && sudo pacman -Rns --noconfirm $(pacman -Qtdq) 2>/dev/null'  # Clean package cache and orphans
alias cache='rm -rf ~/.cache/* && sudo paccache -r'                                # Clear user cache and old packages
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'                 # Check CPU vulnerabilities
alias jctl='journalctl -p 3 -xb'                                                   # Show boot errors

# -----------------------------------------------------------------------------
# System Power
# -----------------------------------------------------------------------------
alias sr='echo "Rebooting the system...\n" && sudo reboot'                          # Reboot system
alias ss='echo "Shutting down the system...\n" && sudo poweroff'                    # Shutdown system
alias bios='systemctl reboot --firmware-setup'                                      # Reboot to UEFI
alias windows='systemctl reboot --boot-loader-entry=auto-windows'                   # Reboot to Windows
alias suspend='systemctl suspend'                                                   # Suspend system
alias hibernate='systemctl hibernate'                                               # Hibernate system

# -----------------------------------------------------------------------------
# File Listing (eza replaces ls)
# -----------------------------------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza -al --color=always --group-directories-first --icons'               # Detailed listing with icons
  alias la='eza -a --color=always --group-directories-first --icons'                # All files with icons
  alias ll='eza -l --color=always --group-directories-first --icons'                # Long format
  alias lt='eza -aT --color=always --group-directories-first --icons'               # Tree listing
  alias l.="eza -a | grep -e '^\.'"                                                 # Show only dotfiles
  alias lh='eza -ahl --color=always --group-directories-first --icons'              # Human-readable sizes
else
  alias ls='ls --color=auto'
  alias ll='ls -lv --group-directories-first'
  alias la='ls -A'
fi

# -----------------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------------
alias ..='cd ..'                                                                   # Go up one directory
alias ...='cd ../..'                                                               # Go up two directories
alias ....='cd ../../..'                                                           # Go up three directories
alias .....='cd ../../../..'                                                       # Go up four directories
alias -- -='cd -'                                                                  # Go to previous directory
alias home='cd ~'                                                                  # Go to home directory
alias docs='cd ~/Documents'                                                        # Go to Documents
alias down='cd ~/Downloads'                                                        # Go to Downloads

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
alias ip='ip addr'                                                                 # Show IP addresses
alias ipa='ip -c -br addr'                                                         # Brief colored IP info
alias myip='curl -s ifconfig.me'                                                   # Show public IP
alias localip='hostname -I'                                                        # Show local IP
alias ports='netstat -tulanp'                                                      # Show all open ports
alias listenports='sudo lsof -i -P -n | grep LISTEN'                               # Show listening ports
alias scanports='nmap -p 1-1000'                                                   # Scan ports 1-1000
alias ping='ping -c 5'                                                             # Ping with 5 packets
alias wget='wget -c'                                                               # Resume wget downloads by default

# -----------------------------------------------------------------------------
# System Monitoring
# -----------------------------------------------------------------------------
alias top='btop'                                                                   # Use btop instead of top
alias htop='btop'                                                                  # Use btop instead of htop
alias hw='hwinfo --short'                                                          # Hardware info summary
alias cpu='lscpu'                                                                  # CPU information
alias gpu='lspci | grep -i vga'                                                    # GPU information
alias mem='free -mt'                                                               # Memory usage
alias gove='cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'             # CPU Governor
alias cpustat='cpupower frequency-info | grep -E "governor|current policy"'        # CPU Power Stats
alias psf='ps auxf'                                                                # Process tree
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'                              # Search processes
alias big='expac -H M "%m\t%n" | sort -h | nl'                                     # Largest installed packages
alias topcpu='ps auxf | sort -nr -k 3 | head -10'                                  # Top 10 CPU processes
alias topmem='ps auxf | sort -nr -k 4 | head -10'                                  # Top 10 memory processes

# -----------------------------------------------------------------------------
# Disk Usage
# -----------------------------------------------------------------------------
alias df='df -h'                                                                   # Human-readable disk usage
alias du='du -h'                                                                   # Human-readable directory size
alias duh='du -h --max-depth=1 | sort -h'                                          # Directory sizes sorted
alias duf='duf'                                                                    # Modern disk usage tool (if installed)

# -----------------------------------------------------------------------------
# Archive Operations
# -----------------------------------------------------------------------------
alias mktar='tar -acf'                                                             # Create tar archive
alias untar='tar -xvf'                                                             # Extract tar archive
alias mkzip='zip -r'                                                               # Create zip archive
alias lstar='tar -tvf'                                                             # List tar contents
alias lszip='unzip -l'                                                             # List zip contents

# -----------------------------------------------------------------------------
# File Operations
# -----------------------------------------------------------------------------
alias cp='cp -iv'                                                                  # Interactive and verbose copy
alias mv='mv -iv'                                                                  # Interactive and verbose move
alias rm='rm -Iv --preserve-root'                                                  # Interactive delete (ask for 3+ files)
alias mkdir='mkdir -pv'                                                            # Create parent directories as needed
alias grep='grep --color=auto'                                                     # Colored grep output
alias diff='diff --color=auto'                                                     # Colored diff output
alias fgrep='fgrep --color=auto'                                                   # Colored fgrep
alias egrep='egrep --color=auto'                                                   # Colored egrep

# -----------------------------------------------------------------------------
# Git Aliases (Replacements for OMZ git plugin)
# -----------------------------------------------------------------------------
alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gb='git branch'
alias gc='git commit -v'
alias gcam='git commit -a -m'
alias gco='git checkout'
alias gd='git diff'
alias gl='git pull'
alias gp='git push'
alias gst='git status'

# -----------------------------------------------------------------------------
# Configuration & Editing
# -----------------------------------------------------------------------------
alias zshconfig='nano ~/.zshrc'                                                      # Edit zsh config
alias zshreload='source ~/.zshrc'                                                    # Reload zsh config
alias aliases='cat ~/.zshrc | grep "^alias" | sed "s/alias //" | column -t -s="# "'  # List all aliases

# -----------------------------------------------------------------------------
# Package Management
# -----------------------------------------------------------------------------
alias unlock='sudo rm /var/lib/pacman/db.lck'                                     # Remove pacman lock
alias rip='expac --timefmt="%d-%m-%Y %T" "%l\t%n %v" | sort | tail -200 | nl'     # Recently installed packages
alias orphans='sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null'                      # Remove orphaned packages

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------
alias weather='curl wttr.in'                                                       # Show weather
alias matrix='cmatrix'                                                             # Matrix effect
alias ports-used='netstat -tulanp | grep ESTABLISHED'                              # Show active connections

# =============================================================================
# Tool Initialization
# =============================================================================

# Add local bin to PATH if it exists
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# Zoxide - Smart cd replacement (use 'z dirname' to jump to frequently used directories)
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'  # Replace cd with zoxide for smart directory jumping
fi

# Starship - Modern prompt with git integration
if command -v starship >/dev/null; then
  eval "$(starship init zsh)"
fi

# Fastfetch - Display system information on shell start
if command -v fastfetch >/dev/null; then
  fastfetch
fi

# =============================================================================
# Additional Functions
# =============================================================================

# Extract any archive type
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"     ;;
      *.tar.gz)    tar xzf "$1"     ;;
      *.bz2)       bunzip2 "$1"     ;;
      *.rar)       unrar x "$1"     ;;
      *.gz)        gunzip "$1"      ;;
      *.tar)       tar xf "$1"      ;;
      *.tbz2)      tar xjf "$1"     ;;
      *.tgz)       tar xzf "$1"     ;;
      *.zip)       unzip "$1"       ;;
      *.Z)         uncompress "$1"  ;;
      *.7z)        7z x "$1"        ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Create directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Find and kill process by name
killp() {
  ps aux | grep -i "$1" | grep -v grep | awk '{print $2}' | xargs sudo kill -9
}

# =============================================================================
# End of Configuration
# =============================================================================
