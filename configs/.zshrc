# =============================================================================
# ZSH
# =============================================================================

# -----------------------------------------------------------------------------
# Ensure correct terminal for SSH and colors
# -----------------------------------------------------------------------------
export TERM=${TERM:-xterm-256color}  # fallback if TERM is not set
[[ -n "$SSH_TTY" ]] && export TERM=xterm-256color

# -----------------------------------------------------------------------------
# Completion (cached, fast)
# -----------------------------------------------------------------------------
autoload -Uz compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.zsh/cache"

[[ -d $HOME/.zsh/cache ]] || mkdir -p "$HOME/.zsh/cache"
compinit -d "$HOME/.zsh/cache/zcompdump"

# -----------------------------------------------------------------------------
# Shell options
# -----------------------------------------------------------------------------
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt EXTENDED_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt CORRECT

HISTFILE=$HOME/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

# -----------------------------------------------------------------------------
# Bash-compatible history -c
# -----------------------------------------------------------------------------
history() {
  if [[ "$1" == "-c" ]]; then
    fc -p
    [[ -n "$HISTFILE" ]] && : >| "$HISTFILE" 2>/dev/null
  else
    builtin history "$@"
  fi
}

# -----------------------------------------------------------------------------
# Keybindings (sane defaults)
# -----------------------------------------------------------------------------
bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^H' backward-kill-word
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# -----------------------------------------------------------------------------
# Plugins (system-installed only)
# -----------------------------------------------------------------------------

# fzf
[[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -f /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh

# autosuggestions
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# syntax highlighting (MUST be last)
[[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] \
  && source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# -----------------------------------------------------------------------------
# PATH
# -----------------------------------------------------------------------------
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"

# -----------------------------------------------------------------------------
# Prompt
# -----------------------------------------------------------------------------
command -v starship >/dev/null && eval "$(starship init zsh)"

# -----------------------------------------------------------------------------
# Navigation (zoxide)
# -----------------------------------------------------------------------------
if command -v zoxide >/dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'
fi

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------

## pacman / system
alias sync='sudo pacman -Syy'
alias update='yay -Syyu && sudo flatpak update'
alias mirror='sudo rate-mirrors --allow-root --save /etc/pacman.d/mirrorlist arch && sudo pacman -Syy'
alias clean='sudo pacman -Sc --noconfirm && yay -Sc --noconfirm && sudo flatpak uninstall --unused && sudo pacman -Rns --noconfirm $(pacman -Qtdq) 2>/dev/null'
alias cache='rm -rf ~/.cache/* && sudo paccache -r'
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias jctl='journalctl -p 3 -xb'
alias orphans='sudo pacman -Rns $(pacman -Qtdq) 2>/dev/null'
alias unlock='sudo rm /var/lib/pacman/db.lck'

## power
alias reboot='sudo reboot'
alias sr='sudo reboot'
alias shutdown='sudo poweroff'
alias ss='sudo poweroff'
alias suspend='systemctl suspend'
alias bios='systemctl reboot --firmware-setup'
alias windows='systemctl reboot --boot-loader-entry=auto-windows'

## ls replacement
if command -v eza >/dev/null; then
  alias ls='eza -al --group-directories-first --icons'
  alias ll='eza -l --icons'
  alias la='eza -a --icons'
  alias lt='eza -T --icons'
else
  alias ls='ls --color=auto'
fi

## file ops
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv --preserve-root'
alias mkdir='mkdir -pv'

## search
alias grep='grep --color=auto'
command -v rg >/dev/null && alias grep='rg'

## git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'

## configuration & editing
alias zshconfig='nano ~/.zshrc'
alias zshreload='source ~/.zshrc'

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  [[ -f "$1" ]] || return 1
  case "$1" in
    *.tar.gz|*.tgz) tar xzf "$1" ;;
    *.tar.bz2)      tar xjf "$1" ;;
    *.tar.xz)       tar xJf "$1" ;;
    *.zip)          unzip "$1"  ;;
    *.7z)           7z x "$1"   ;;
    *) echo "unknown archive" ;;
  esac
}

# -----------------------------------------------------------------------------
# Optional eye-candy (disable for max speed)
# -----------------------------------------------------------------------------
command -v fastfetch >/dev/null && fastfetch

# =============================================================================
# End
# =============================================================================
