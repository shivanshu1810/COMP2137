#!/bin/bash
# COMP2137 - Assignment 2
# Author: Shivanshu Sharma
# Description: Ensures server1 is configured as per assignment requirements.
# This script is idempotent — safe to run multiple times.

set -e

BACKUP_DIR="/var/backups/assignment2-backups-$(date +%Y%m%d-%H%M%S)"
TARGET_IP="192.168.16.21"
TARGET_CIDR="24"
TARGET_INTERFACE="eth0"
NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
HOSTNAME="server1"
USERS=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)
DENNIS_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

echo "[INFO] Starting assignment2.sh — backups will be in $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# --- 1. Detect eth0 or private network interface ---
if ip a | grep -q "192\.168\.16\."; then
    IFACE=$(ip -o addr show | grep "192\.168\.16\." | awk '{print $2}')
else
    IFACE="eth0"
fi
echo "[ OK ] Found interface with 192.168.16.*: $IFACE"

# --- 2. Backup existing netplan file ---
if [ -f "$NETPLAN_FILE" ]; then
    cp "$NETPLAN_FILE" "$BACKUP_DIR/$(basename $NETPLAN_FILE).bak"
    echo "[ OK ] Backed up $NETPLAN_FILE -> $BACKUP_DIR"
else
    echo "[ERR ] No netplan file found at $NETPLAN_FILE"
    exit 1
fi

# --- 3. Write clean, valid YAML configuration ---
echo "[INFO] Updating Netplan configuration..."
cat <<EOF > "$NETPLAN_FILE"
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - $TARGET_IP/$TARGET_CIDR
EOF
echo "[ OK ] Wrote clean Netplan configuration to $NETPLAN_FILE"

# --- 4. Apply configuration ---
echo "[INFO] Applying Netplan configuration..."
if netplan try --timeout 15; then
    netplan apply
    echo "[ OK ] Network configuration applied successfully."
else
    echo "[ERR ] Netplan failed validation. Restoring backup..."
    cp "$BACKUP_DIR/$(basename $NETPLAN_FILE).bak" "$NETPLAN_FILE"
    exit 1
fi

# --- 5. Ensure /etc/hosts entry ---
echo "[INFO] Updating /etc/hosts..."
sed -i "/$HOSTNAME/d" /etc/hosts
echo "$TARGET_IP    $HOSTNAME" >> /etc/hosts
echo "[ OK ] /etc/hosts entry updated."

# --- 6. Install required software ---
echo "[INFO] Ensuring required packages (apache2, squid)..."
apt-get update -qq
apt-get install -y apache2 squid -qq
systemctl enable --now apache2 squid
echo "[ OK ] apache2 and squid are installed and running."

# --- 7. Create required user accounts ---
echo "[INFO] Creating required user accounts..."
for user in "${USERS[@]}"; do
    if id "$user" &>/dev/null; then
        echo "   -> $user already exists."
    else
        useradd -m -s /bin/bash "$user"
        echo "   -> Created user $user"
    fi

    mkdir -p /home/$user/.ssh
    chmod 700 /home/$user/.ssh

    if [ ! -f /home/$user/.ssh/id_rsa ]; then
        ssh-keygen -t rsa -N "" -f /home/$user/.ssh/id_rsa >/dev/null
    fi
    if [ ! -f /home/$user/.ssh/id_ed25519 ]; then
        ssh-keygen -t ed25519 -N "" -f /home/$user/.ssh/id_ed25519 >/dev/null
    fi

    cat /home/$user/.ssh/id_rsa.pub /home/$user/.ssh/id_ed25519.pub > /home/$user/.ssh/authorized_keys
    chown -R $user:$user /home/$user/.ssh
    chmod 600 /home/$user/.ssh/authorized_keys
done
echo "[ OK ] All user accounts verified."

# --- 8. Ensure dennis has sudo access and extra key ---
if ! groups dennis | grep -q sudo; then
    usermod -aG sudo dennis
    echo "[ OK ] Added dennis to sudo group."
fi
grep -q "$DENNIS_KEY" /home/dennis/.ssh/authorized_keys || echo "$DENNIS_KEY" >> /home/dennis/.ssh/authorized_keys
echo "[ OK ] Added course-provided SSH key to dennis."

echo "[SUCCESS] Assignment2 configuration complete!"
