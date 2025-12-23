# =============================================================================
# ZSH Configuration
# =============================================================================

# -----------------------------------------------------------------------------
# Performance: Skip global compinit (done in /etc/zsh/zshrc)
# -----------------------------------------------------------------------------
skip_global_compinit=1

# -----------------------------------------------------------------------------
# Terminal setup
# -----------------------------------------------------------------------------
export TERM=${TERM:-xterm-256color}
[[ -n "$SSH_TTY" ]] && export TERM=xterm-256color

# -----------------------------------------------------------------------------
# Shell options
# -----------------------------------------------------------------------------
setopt AUTO_CD                   # cd by typing directory name
setopt INTERACTIVE_COMMENTS      # allow comments in interactive shell
setopt EXTENDED_HISTORY          # save timestamp and duration
setopt SHARE_HISTORY             # share history across sessions
setopt HIST_IGNORE_ALL_DUPS      # remove older duplicate entries
setopt HIST_REDUCE_BLANKS        # remove superfluous blanks
setopt HIST_IGNORE_SPACE         # ignore commands starting with space
setopt HIST_VERIFY               # show command with history expansion before running
setopt CORRECT                   # command correction
setopt NO_BEEP                   # no beep on error
setopt PROMPT_SUBST              # enable prompt substitution

HISTFILE=$HOME/.zsh_history
HISTSIZE=50000                   # increased for better history
SAVEHIST=50000

# -----------------------------------------------------------------------------
# PATH
# -----------------------------------------------------------------------------
typeset -U PATH path             # keep PATH entries unique
path=("$HOME/.local/bin" $path)
export PATH

# -----------------------------------------------------------------------------
# Completion system
# -----------------------------------------------------------------------------
autoload -Uz compinit

# Cache completion for better performance
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.zsh/cache"

# Completion styling
zstyle ':completion:*' menu select                           # interactive menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case insensitive
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"     # colored completion
zstyle ':completion:*' group-name ''                         # group results by category
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'
zstyle ':completion:*' squeeze-slashes true                  # handle // in paths
zstyle ':completion:*:cd:*' ignore-parents parent pwd        # don't complete current directory

# Speed up compinit (check once per day)
[[ -d $HOME/.zsh/cache ]] || mkdir -p "$HOME/.zsh/cache"
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
  compinit -d "$HOME/.zsh/cache/zcompdump"
else
  compinit -C -d "$HOME/.zsh/cache/zcompdump"
fi

# -----------------------------------------------------------------------------
# Keybindings (Emacs mode)
# -----------------------------------------------------------------------------
bindkey -e
bindkey '^[[H'      beginning-of-line      # Home
bindkey '^[[F'      end-of-line            # End
bindkey '^[[3~'     delete-char            # Delete
bindkey '^H'        backward-kill-word     # Ctrl+Backspace
bindkey '^[[1;5C'   forward-word           # Ctrl+Right
bindkey '^[[1;5D'   backward-word          # Ctrl+Left
bindkey '^[[Z'      reverse-menu-complete  # Shift+Tab

# Alt+Backspace for backward-kill-word
bindkey '^[^?'      backward-kill-word
bindkey '^[^H'      backward-kill-word

# -----------------------------------------------------------------------------
# History search (up/down arrows)
# -----------------------------------------------------------------------------
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search      # Up arrow
bindkey '^[[B' down-line-or-beginning-search    # Down arrow

# -----------------------------------------------------------------------------
# Bash-compatible history -c
# -----------------------------------------------------------------------------
history() {
  if [[ "$1" == "-c" ]]; then
    echo -n "Clear history? [y/N] "
    read -q && {
      fc -p
      [[ -f "$HISTFILE" ]] && rm -f "$HISTFILE"
      echo "\nHistory cleared."
    } || echo "\nCancelled."
  else
    builtin history "$@"
  fi
}

# -----------------------------------------------------------------------------
# FZF integration
# -----------------------------------------------------------------------------
if [[ -f /usr/share/fzf/key-bindings.zsh ]]; then
  source /usr/share/fzf/key-bindings.zsh
  source /usr/share/fzf/completion.zsh

  # FZF settings
  export FZF_DEFAULT_OPTS="
    --height 40%
    --layout=reverse
    --border
    --info=inline
    --color=fg:#d0d0d0,bg:#121212,hl:#5f87af
    --color=fg+:#d0d0d0,bg+:#262626,hl+:#5fd7ff
    --color=info:#afaf87,prompt:#d7005f,pointer:#af5fff
    --color=marker:#87ff00,spinner:#af5fff,header:#87afaf"

  # Use fd if available
  if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi
fi

# -----------------------------------------------------------------------------
# Zsh-autosuggestions
# -----------------------------------------------------------------------------
# Try multiple possible locations for zsh-autosuggestions (from package manager)
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'        # subtle gray
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)  # try history first, then completion
  ZSH_AUTOSUGGEST_USE_ASYNC=1                   # async for better performance
  bindkey '^ ' autosuggest-accept  # Ctrl+Space to accept
elif [[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
  ZSH_AUTOSUGGEST_USE_ASYNC=1
  bindkey '^ ' autosuggest-accept
fi

# -----------------------------------------------------------------------------
# Zoxide (smart cd)
# -----------------------------------------------------------------------------
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'
  alias cdi='zi'  # interactive selection
fi

# -----------------------------------------------------------------------------
# Starship prompt
# -----------------------------------------------------------------------------
if command -v starship >/dev/null; then
  eval "$(starship init zsh)"
fi

# -----------------------------------------------------------------------------
# Package management aliases (Fedora)
# -----------------------------------------------------------------------------
alias sync='sudo dnf update --refresh'
alias update='sudo dnf update && sudo dnf upgrade && sudo flatpak update'
alias clean='sudo dnf -y autoremove && sudo dnf clean all && sudo flatpak uninstall --unused'
alias cache='rm -rf ~/.cache/*'
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias sr='sudo reboot'
alias ss='sudo poweroff'
alias jctl='journalctl -p 3 -xb'
alias orphans='sudo dnf autoremove -y'
alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'

# -----------------------------------------------------------------------------
# Power management
# -----------------------------------------------------------------------------
alias reboot='sudo systemctl reboot'
alias shutdown='sudo systemctl poweroff'
alias suspend='systemctl suspend'
alias bios='systemctl reboot --firmware-setup'

# -----------------------------------------------------------------------------
# Modern ls with eza
# -----------------------------------------------------------------------------
if command -v eza >/dev/null; then
  alias ls='eza -al --color=always --group-directories-first --icons'  # preferred listing
  alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
  alias ll='eza -l --color=always --group-directories-first --icons'  # long format
  alias lt='eza -aT --color=always --group-directories-first --icons'  # tree listing
  alias l.="eza -a | grep -e '^\.'"                                   # show only dotfiles
  alias l='eza -lah --icons --git'
else
  alias ls='ls --color=auto -h'
  alias ll='ls -lh'
  alias la='ls -lAh'
fi

# -----------------------------------------------------------------------------
# File operations (safe)
# -----------------------------------------------------------------------------
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv --preserve-root'
alias mkdir='mkdir -pv'
alias grep='grep --color=auto'
command -v rg >/dev/null && alias grep='rg'
command -v bat >/dev/null && alias cat='bat --paging=never'

# -----------------------------------------------------------------------------
# Navigation
# -----------------------------------------------------------------------------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
alias ip='ip addr'
alias ports='netstat -tulanp'
alias ping='ping -c 5'

# -----------------------------------------------------------------------------
# System Monitoring
# -----------------------------------------------------------------------------
alias top='btop'
alias htop='btop'
alias hw='hwinfo --short'
alias cpu='lscpu'
alias mem="free -mt"
alias psf='ps auxf'

# -----------------------------------------------------------------------------
# Disk Usage
# -----------------------------------------------------------------------------
alias df='df -h'
alias du='du -h'
alias duh='du -h --max-depth=1'

# -----------------------------------------------------------------------------
# Archive Operations
# -----------------------------------------------------------------------------
alias tar='tar -acf '
alias untar='tar -zxvf '
alias zip='zip -r'
alias unzip='unzip'

# -----------------------------------------------------------------------------
# Git shortcuts
# -----------------------------------------------------------------------------
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'
alias glog='git log --oneline --graph --decorate'

# -----------------------------------------------------------------------------
# Config shortcuts
# -----------------------------------------------------------------------------
alias zshconfig="nano ~/.zshrc"
alias zshreload='source ~/.zshrc && echo "✓ Config reloaded"'

# -----------------------------------------------------------------------------
# Utility functions
# -----------------------------------------------------------------------------

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

# Find and cd to directory
fcd() {
  local dir
  dir=$(find ${1:-.} -type d 2>/dev/null | fzf +m) && cd "$dir"
}

# -----------------------------------------------------------------------------
# Zsh-syntax-highlighting (must be last)
# -----------------------------------------------------------------------------
# Try multiple possible locations for zsh-syntax-highlighting (from package manager)
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  
  # Syntax highlighting styles
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
  ZSH_HIGHLIGHT_STYLES[command]='fg=green,bold'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan,bold'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=yellow,bold'
  ZSH_HIGHLIGHT_STYLES[function]='fg=blue,bold'
  ZSH_HIGHLIGHT_STYLES[command-not-found]='fg=red,bold'
elif [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  
  # Syntax highlighting styles
  ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern cursor)
  ZSH_HIGHLIGHT_STYLES[command]='fg=green,bold'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=cyan,bold'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=yellow,bold'
  ZSH_HIGHLIGHT_STYLES[function]='fg=blue,bold'
  ZSH_HIGHLIGHT_STYLES[command-not-found]='fg=red,bold'
fi

# -----------------------------------------------------------------------------
# Welcome message
# -----------------------------------------------------------------------------
if command -v fastfetch >/dev/null && [[ -z "$TMUX" ]]; then
  fastfetch
fi

# =============================================================================
# End of configuration
# =============================================================================

