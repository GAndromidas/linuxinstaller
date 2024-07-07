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

# Directory listing aliases
alias la='ls -Alh'                # show hidden files
alias ls='ls -aFh --color=always' # add colors and file type extensions
alias lx='ls -lXBh'               # sort by extension
alias lk='ls -lSrh'               # sort by size
alias lc='ls -ltcrh'              # sort by change time
alias lu='ls -lturh'              # sort by access time
alias lr='ls -lRh'                # recursive ls
alias lt='ls -ltrh'               # sort by date
alias lm='ls -alh | more'         # pipe through 'more'
alias lw='ls -XAhl'               # wide listing format
alias ll='ls -Fls'                # long listing format
alias labc='ls -lap'              # alphabetical sort
alias lf="ls -l | egrep -v '^d'"  # files only
alias ldir="ls -l | egrep '^d'"   # directories only
alias lla='ls -Al'                # List and Hidden Files
alias las='ls -A'                 # Hidden Files
alias lls='ls -l'                 # List

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# File Operations
alias cpv='rsync -ah --info=progress2'
alias mv='mv -i'
alias cp='cp -i'
alias rm='rm -i'

# Search
alias f='find . -name'
alias grep='grep --color=auto'

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

# Disk Usage
alias df='df -h'
alias du='du -h'
alias duh='du -h --max-depth=1'

# Tar and Zip Operations
alias tarxz='tar -cJf'
alias tarcz='tar -czf'
alias tarxzv='tar -xJf'
alias tarczv='tar -xzf'
alias zip='zip -r'
alias unzip='unzip'

# Miscellaneous aliases
alias zshconfig="nano ~/.zshrc"
alias unlock="sudo rm /var/lib/pacman/db.lck"

# Load additional tools
fastfetch --cpu-temp --gpu-temp
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
