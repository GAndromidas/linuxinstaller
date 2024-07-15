# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Themes
ZSH_THEME="agnoster"
DEFAULT_USER=$USER

# Oh-My-ZSH Auto Update
zstyle ':omz:update' mode auto      # update automatically without asking

# Plugins
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# Aliases

# System maintenance aliases
alias sync='sudo pacman -Syy'
alias update='yay -Syyu && sudo flatpak update'
alias mirror='sudo reflector --verbose --protocol https --latest 10 --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syyy'
alias clean='sudo pacman -Sc --noconfirm && yay -Sc --noconfirm && sudo pacman -Rns $(pacman -Qtdq)'
alias cache='rm -rf ~/.cache/* && sudo paccache -r'
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias sr='sudo reboot'
alias ss='sudo poweroff'
alias jctl='journalctl -p 3 -xb'

# Replace ls with eza
alias ls='eza -al --color=always --group-directories-first --icons' # preferred listing
alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
alias ll='eza -l --color=always --group-directories-first --icons'  # long format
alias lt='eza -aT --color=always --group-directories-first --icons' # tree listing
alias l.="eza -a | grep -e '^\.'"                                   # show only dotfiles

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# Networking
alias ip='ip addr'
alias ports='netstat -tulanp'
alias ping='ping -c 5'

# System Monitoring
alias top='btop'
alias hw='hwinfo --short'
alias cpu='lscpu'
alias mem="free -mt"
alias psf='ps auxf'
alias big="expac -H M '%m\t%n' | sort -h | nl"              # Sort installed packages according to size in MB

# Disk Usage
alias df='df -h'
alias du='du -h'
alias duh='du -h --max-depth=1'

# Tar and Zip Operations
alias tar='tar -acf '
alias untar='tar -zxvf '
alias zip='zip -r'
alias unzip='unzip'

# Miscellaneous aliases
alias zshconfig="nano ~/.zshrc"
alias unlock="sudo rm /var/lib/pacman/db.lck"

# Recent installed packages
alias rip="expac --timefmt='%d-%m-%Y %T' '%l\t%n %v' | sort | tail -200 | nl"

# Load additional tools
fastfetch --cpu-temp --gpu-temp
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
