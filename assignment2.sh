#!/bin/bash
###############################################################################
#                          ASSIGNMENT 2 SCRIPT
#            Configure server1: IP, packages, users, SSH keys
###############################################################################

set -euo pipefail

TARGET_IP="192.168.16.21"
MGMT_IP="172.16.1.241"
NETPLAN_FILE="/etc/netplan/10-lxc.yaml"
HOSTS_FILE="/etc/hosts"
DENNIS_EXTRA_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"
USERS=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)
PACKAGES=(apache2 squid)

echo "==================== Assignment 2 Script ===================="

# ---------------------------
# NETPLAN: update server1 IP only
# ---------------------------
update_netplan() {
    echo "[INFO] Updating netplan IP for server1..."
    
    if [ ! -f "$NETPLAN_FILE" ]; then
        echo "[INFO] Netplan file not found. Creating default..."
        sudo bash -c "cat > $NETPLAN_FILE <<EOF
network:
    version: 2
    ethernets:
        eth0:
            addresses: [$TARGET_IP/24]
            routes:
              - to: default
                via: 192.168.16.2
            nameservers:
                addresses: [192.168.16.2]
                search: [home.arpa, localdomain]
        eth1:
            addresses: [$MGMT_IP/24]
EOF"
    else
        # Only replace eth0 address matching 192.168.16.X
        sudo sed -i -E "s#(addresses:\s*\[192\.168\.16\.)[0-9]{1,3}(/24\])#\1${TARGET_IP##*.}\2#" "$NETPLAN_FILE"
    fi

    sudo netplan apply
    echo "[OK] Netplan applied"
}

# ---------------------------
# HOSTS: update server1 entry
# ---------------------------
update_hosts() {
    echo "[INFO] Updating /etc/hosts for server1..."
    
    # Ensure server1 line points to TARGET_IP
    sudo awk -v ip="$TARGET_IP" '
    BEGIN { found=0 }
    {
        if ($0 ~ /(^|[[:space:]])server1([[:space:]]|$)/) {
            if (!found) { print ip " server1"; found=1 }
        } else { print $0 }
    }
    END { if (!found) print ip " server1" }
    ' "$HOSTS_FILE" | sudo tee "$HOSTS_FILE.tmp" >/dev/null

    sudo mv "$HOSTS_FILE.tmp" "$HOSTS_FILE"
    sudo chmod 644 "$HOSTS_FILE"
    echo "[OK] /etc/hosts updated"
}

# ---------------------------
# PACKAGES: install apache2 and squid
# ---------------------------
install_packages() {
    echo "[INFO] Updating package lists..."
    sudo apt update -y

    for idx in "${!PACKAGES[@]}"; do
        pkg="${PACKAGES[$idx]}"
        echo "--------------------------------------------------"
        echo "[INFO] Processing package [$idx]: $pkg"

        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "[INFO] Package $pkg already installed"
        else
            echo "[INFO] Installing $pkg..."
            if sudo apt install -y "$pkg"; then
                echo "[OK] Installed $pkg"
            else
                echo "[ERROR] Failed to install $pkg" >&2
                continue
            fi
        fi

        # Enable and start the service
        echo "[INFO] Enabling and starting service $pkg..."
        if sudo systemctl enable --now "$pkg"; then
            echo "[OK] Service $pkg is enabled and running"
        else
            echo "[ERROR] Failed to enable/start $pkg" >&2
        fi
    done
    echo "[INFO] Package installation complete"
}


# ---------------------------
# USERS: create users, SSH keys, authorized_keys
# ---------------------------
setup_users() {
    echo "[INFO] Creating users and setting up SSH keys..."

    for u in "${USERS[@]}"; do
        if ! id -u "$u" >/dev/null 2>&1; then
            sudo useradd -m -s /bin/bash "$u"
            echo "[INFO] Created user $u"
        fi

        # Ensure home and shell
        sudo usermod -d "/home/$u" -s /bin/bash "$u" >/dev/null 2>&1 || true

        # Add dennis to sudo
        if [ "$u" == "dennis" ]; then
            sudo usermod -aG sudo "$u" >/dev/null 2>&1 || true
        fi

        ssh_dir="/home/$u/.ssh"
        auth_file="$ssh_dir/authorized_keys"
        sudo mkdir -p "$ssh_dir"
        sudo touch "$auth_file"
        sudo chown -R "$u:$u" "$ssh_dir"
        sudo chmod 700 "$ssh_dir"
        sudo chmod 600 "$auth_file"

        # Generate SSH keys if missing
        if [ ! -f "$ssh_dir/id_rsa" ]; then
            sudo -u "$u" ssh-keygen -t rsa -b 2048 -f "$ssh_dir/id_rsa" -N "" -q
        fi
        if [ ! -f "$ssh_dir/id_ed25519" ]; then
            sudo -u "$u" ssh-keygen -t ed25519 -f "$ssh_dir/id_ed25519" -N "" -q
        fi

        # Add public keys to authorized_keys
        for pub in "$ssh_dir/id_rsa.pub" "$ssh_dir/id_ed25519.pub"; do
            if ! grep -Fxq "$(cat "$pub")" "$auth_file"; then
                cat "$pub" | sudo tee -a "$auth_file" >/dev/null
            fi
        done

        # Add extra key for dennis
        if [ "$u" == "dennis" ]; then
            if ! grep -Fxq "$DENNIS_EXTRA_KEY" "$auth_file"; then
                echo "$DENNIS_EXTRA_KEY" | sudo tee -a "$auth_file" >/dev/null
            fi
        fi
    done
}

# ---------------------------
# SUMMARY
# ---------------------------
print_summary() {
    echo "==================== Summary ===================="
    echo "Server1 IP: $TARGET_IP"
    echo "Management IP: $MGMT_IP"
    echo "Installed packages: ${PACKAGES[*]}"
    echo "Users created: ${USERS[*]}"
    echo "SSH keys generated for all users; extra key added for dennis"
    echo "================================================="
}

# ---------------------------
# MAIN
# ---------------------------
update_netplan
update_hosts
install_packages
setup_users
print_summary
