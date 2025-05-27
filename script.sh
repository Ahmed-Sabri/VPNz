#!/bin/bash

# Function to check if a command was successful
check_command() {
    if [ $? -ne 0 ]; then
        echo "Error: $1"
        exit 1
    fi
}

# Function to prompt for yes/no
prompt_yn() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

# Update and upgrade system
echo "Updating and upgrading system..."
sudo apt update -y && sudo apt full-upgrade -y
check_command "Failed to update and upgrade system"

# Install required packages
echo "Installing required packages..."
sudo apt install --upgrade python3-update-manager update-manager-core curl gpg python3 python3-pip iptables -y
check_command "Failed to install required packages"

# Install ZeroTier
if ! command -v zerotier-cli &> /dev/null; then
    echo "Installing ZeroTier..."
    curl -s https://install.zerotier.com | sudo bash
    check_command "Failed to install ZeroTier"
else
    echo "ZeroTier is already installed."
fi

# Join ZeroTier network
read -p "Enter your ZeroTier Network ID: " NETWORK_ID
sudo zerotier-cli join $NETWORK_ID
check_command "Failed to join ZeroTier network"

# Enable IP forwarding
echo "Enabling IP forwarding..."
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -w net.ipv4.ip_forward=1
check_command "Failed to enable IP forwarding"

# Extract interface names
PHY_IFACE=$(ip addr | awk '/^[0-9]+: e/{print $2}' | cut -d ':' -f 1 | head -n1)
ZT_IFACE=$(ip addr | awk '/^[0-9]+: z/{print $2}' | cut -d ':' -f 1 | head -n1)

echo "Physical interface: $PHY_IFACE"
echo "ZeroTier interface: $ZT_IFACE"

# Set up iptables rules
echo "Setting up iptables rules..."
sudo iptables -t nat -A POSTROUTING -o $PHY_IFACE -j MASQUERADE
sudo iptables -A FORWARD -i $PHY_IFACE -o $ZT_IFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i $ZT_IFACE -o $PHY_IFACE -j ACCEPT
check_command "Failed to set up iptables rules"

# Install iptables-persistent
echo "Installing iptables-persistent..."
sudo DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -y
check_command "Failed to install iptables-persistent"

# Save iptables rules
echo "Saving iptables rules..."
sudo bash -c 'iptables-save > /etc/iptables/rules.v4'
check_command "Failed to save iptables rules"

echo "VPN server setup complete!"
echo "Make sure to enable 'Allow Default Route Override' in your ZeroTier network settings."

# Prompt for reboot
if prompt_yn "Do you want to reboot the system now?"; then
    sudo reboot
else
    echo "Please reboot your system manually to apply all changes."
fi
