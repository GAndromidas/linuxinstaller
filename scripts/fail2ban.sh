#!/bin/bash

# Color functions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to install Fail2ban
install_fail2ban() {
    echo -e "${YELLOW}Installing Fail2ban...${NC}"
    if sudo pacman -S --noconfirm fail2ban; then
        echo -e "${GREEN}Fail2ban installed successfully.${NC}"
    else
        echo -e "${RED}Failed to install Fail2ban.${NC}"
        exit 1
    fi
}

# Function to configure Fail2ban
configure_fail2ban() {
    echo -e "${YELLOW}Configuring Fail2ban...${NC}"
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban

    # Configure jail.local
    sudo bash -c 'cat > /etc/fail2ban/jail.local' << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8
bantime  = 600
findtime  = 600
maxretry = 3

[sshd]
enabled = true
port    = ssh
logpath = /var/log/auth.log
backend = systemd
EOF

    sudo systemctl restart fail2ban
}

# Main script execution
main() {
    install_fail2ban
    configure_fail2ban

    echo -e "${GREEN}Fail2ban installation and configuration completed.${NC}"
}

# Run the main function
main