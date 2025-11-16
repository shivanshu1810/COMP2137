#!/bin/bash
# COMP2137 - Assignment 2
# Author: Shivanshu Sharma
# Description: Ensures server1 is configured as per assignment requirements.
# This script is robust, idempotent, and provides clear, labeled output.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration Variables ---
TARGET_IP="192.168.16.21"
TARGET_CIDR="24"
# MODIFIED: NETPLAN_FILE will now be dynamically determined
NETPLAN_DIR="/etc/netplan" 
HOSTNAME="server1"
BACKUP_DIR="/var/backups/assignment2-backups-$(date +%Y%m%d-%H%M%S)"
PACKAGES=("apache2" "squid")

# Required external key for dennis
DENNIS_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm"

# All users list
USERS=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)

# --- Helper Functions for Labeled Output ---

# Function to print messages with status labels and color
log() {
    local status="$1"
    local message="$2"
    # Use ANSI color codes for visibility
    case "$status" in
        INFO) echo -e "[\033[36mINFO\033[0m] ${message}";;
        OK) echo -e "[\033[32m OK \033[0m] ${message}";;
        WARN) echo -e "[\033[33mWARN\033[0m] ${message}";;
        ERR) echo -e "[\033[31mERR \033[0m] ${message}" >&2; exit 1;;
        SUCCESS) echo -e "\n[\033[32mSUCCESS\033[0m] ${message}\n";;
        *) echo "${message}";;
    esac
}

# Function to fix repository sources (targets the 'no Release file' error by overwriting)
fix_repo_sources() {
    local sources_file="/etc/apt/sources.list"
    log INFO "Checking $sources_file for repository validity."

    # Perform fix only if the file exists and seems to point to standard Ubuntu URLs (Jammy)
    if [ -f "$sources_file" ] && grep -q "jammy" "$sources_file"; then
        if ! grep -q "old-releases" "$sources_file"; then
            log INFO "Ubuntu Jammy detected. Overwriting sources.list with clean 'old-releases' mirror to resolve repository errors."
            
            # Backup the current sources file
            cp "$sources_file" "$BACKUP_DIR/$(basename $sources_file)"
            log OK "Backed up $sources_file to $BACKUP_DIR"
        fi

        # Overwrite the file with a known clean, minimal configuration pointing to old-releases
        cat <<EOF > "$sources_file"
deb http://old-releases.ubuntu.com/ubuntu/ jammy main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse
EOF
        log OK "Repository sources completely overwritten with clean old-releases configuration."
    else
        log OK "Repository sources file status looks acceptable or doesn't need old-releases fix."
    fi
}


# Function to check and install/start a package (Idempotent)
ensure_package() {
    local package_name="$1"
    
    # 1. Installation Check (only install if not present)
    if ! dpkg -l | grep -q "^ii.*${package_name}"; then
        log INFO "Installing required package: ${package_name}..."
        # NOTE: apt update moved outside of this function to run only once after fixing sources
        if ! apt-get install -y "${package_name}" > /dev/null 2>&1; then
            log ERR "Failed to install package ${package_name}. Check package source/connectivity."
        fi
    fi

    # 2. Service Running Check (only start if not active)
    if systemctl is-active --quiet "${package_name}"; then
        log OK "Service ${package_name} is installed and running."
    else
        log INFO "Starting and enabling service ${package_name}..."
        # Start and enable the service and check for errors
        if systemctl enable --now "${package_name}" > /dev/null 2>&1; then
            log OK "Service ${package_name} is installed and running."
        else
            log ERR "Failed to start/enable service ${package_name}."
        fi
    fi
}

# --- Main Execution ---

log INFO "Starting assignment2.sh — backups will be in $BACKUP_DIR"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  log ERR "This script must be run with sudo or as root."
fi

# Ensure Backup Directory Exists
if ! mkdir -p "$BACKUP_DIR"; then
    log ERR "Failed to create backup directory $BACKUP_DIR. Check permissions."
fi

# --- 1. Network Interface Detection ---
log INFO "--- 1. Detecting Interface ---"
# Reliably find the interface name attached to the 192.168.16.* network
IFACE=$(ip -4 -o a | awk '/inet 192\.168\.16\./ {print $2}' | head -n 1)

if [[ -z "$IFACE" ]]; then
    log ERR "Could not find interface on 192.168.16.* network. Cannot proceed."
fi
log OK "Target interface identified: $IFACE"


# --- 2. Netplan Configuration (Idempotent) ---
log INFO "--- 2. Configuring Netplan ---"

# Dynamic file detection
# Find the first .yaml file in the netplan directory.
NETPLAN_FILE=$(find "$NETPLAN_DIR" -maxdepth 1 -type f -name "*.yaml" | head -n 1)

if [ -z "$NETPLAN_FILE" ]; then
    log ERR "No Netplan YAML file found in $NETPLAN_DIR. Cannot proceed with network configuration."
fi
log OK "Identified Netplan configuration file: $NETPLAN_FILE"

# Idempotency check: Check if the required IP/interface combination is already present
if grep -qF "${IFACE}:" "$NETPLAN_FILE" && grep -qF "${TARGET_IP}/${TARGET_CIDR}" "$NETPLAN_FILE" && grep -qF "8.8.8.8" "$NETPLAN_FILE"; then
    log OK "Netplan configuration already correct and includes DNS. Skipping modification/apply."
else
    log INFO "Configuration mismatch detected. Updating Netplan to include DNS."
    
    # Backup existing netplan file
    cp "$NETPLAN_FILE" "$BACKUP_DIR/$(basename $NETPLAN_FILE)"
    log OK "Backed up $NETPLAN_FILE to $BACKUP_DIR"

    # Write clean, valid YAML configuration, NOW INCLUDING NAMESERVERS
    cat <<EOF > "$NETPLAN_FILE"
network:
  version: 2
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - $TARGET_IP/$TARGET_CIDR
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
        search: [comp2137.local]
EOF
    log OK "Wrote clean Netplan configuration (including DNS) to $NETPLAN_FILE"

    # Apply configuration with safe mode/revert
    log INFO "Applying Netplan configuration (accept changes if prompted)..."
    if netplan try --timeout 15; then
        netplan apply
        log OK "Network configuration applied successfully."
    else
        # Restore the backup file on failure
        log ERR "Netplan failed validation. Restoring backup..."
        cp "$BACKUP_DIR/$(basename $NETPLAN_FILE)" "$NETPLAN_FILE"
        exit 1
    fi
fi

# --- 3. /etc/hosts entry (Idempotent) ---
log INFO "--- 3. Updating /etc/hosts ---"
HOSTS_LINE="$TARGET_IP\t$HOSTNAME"

# Idempotency check: Is the correct line already present?
if grep -qE "^${TARGET_IP}\s+${HOSTNAME}$" /etc/hosts; then
    log OK "/etc/hosts entry is already correct."
else
    # Remove any existing server1 entry (old IPs)
    log INFO "Removing old hostname entries for $HOSTNAME..."
    # Use ' $' to ensure we only target 'server1' at the end of a line, avoiding accidental deletion of other hostnames
    sed -i "/ ${HOSTNAME}$/d" /etc/hosts
    # Add the new correct entry
    echo -e "$HOSTS_LINE" >> /etc/hosts
    log OK "New /etc/hosts entry added: $HOSTS_LINE."
fi


# --- 4. Install required software (Idempotent) ---
log INFO "--- 4. Installing and Starting Required Software ---"

# Step 4a: Fix repository sources before attempting update
fix_repo_sources

# Step 4b: Update package lists once after fixing sources
log INFO "Running final apt clean and update..."
# Clean the local package cache to force a fresh index download
if apt-get clean > /dev/null 2>&1; then
    log OK "APT cache cleaned successfully."
else
    log WARN "APT clean reported issues. Continuing anyway."
fi

# Update package lists
if ! apt-get update -qq; then
    log WARN "'apt update' reported harmless issues. Continuing installation attempts."
fi

# Step 4c: Loop through and ensure packages
for pkg in "${PACKAGES[@]}"; do
    ensure_package "$pkg"
done


# --- 5. Create and Configure User Accounts (Idempotent) ---
log INFO "--- 5. Configuring User Accounts and SSH ---"

for user in "${USERS[@]}"; do
    HOME_DIR="/home/$user"
    AUTHORIZED_KEYS="$HOME_DIR/.ssh/authorized_keys"

    # A. User Creation Check (Creates if needed, ensures /bin/bash shell)
    if id "$user" &>/dev/null; then
        log OK "User $user already exists."
    else
        # -m: create home directory, -s: set shell to bash
        if useradd -m -s /bin/bash "$user"; then
            log INFO "Created user $user (Home: $HOME_DIR, Shell: /bin/bash)."
        else
            log ERR "Failed to create user $user."
        fi
    fi

    # B. SSH Setup: Directory structure and ownership/permissions
    # This block ensures permissions are correct even if the user already existed
    mkdir -p "$HOME_DIR/.ssh"
    chown -R "$user:$user" "$HOME_DIR"
    chmod 700 "$HOME_DIR/.ssh"
    touch "$AUTHORIZED_KEYS"
    chmod 600 "$AUTHORIZED_KEYS"
    
    # C. Generate SSH keys (Idempotent: checks for private key existence)
    for algo in "rsa" "ed25519"; do
        SSH_PRIVATE_KEY="$HOME_DIR/.ssh/id_${algo}"
        
        # Key Generation Check
        if [ ! -f "$SSH_PRIVATE_KEY" ]; then
            # Generate key silently
            ssh-keygen -t "$algo" -N "" -f "$SSH_PRIVATE_KEY" >/dev/null 2>&1
            log INFO "Generated $algo key for $user."
        fi

        # Add generated public key to authorized_keys (Idempotence check)
        GENERATED_PUBKEY=$(cat "${SSH_PRIVATE_KEY}.pub")
        if ! grep -qF "$GENERATED_PUBKEY" "$AUTHORIZED_KEYS"; then
            echo "$GENERATED_PUBKEY" >> "$AUTHORIZED_KEYS"
            log INFO "Added generated $algo public key to $user's authorized_keys."
        fi
    done
    
    # D. Special Configuration for 'dennis'
    if [ "$user" == "dennis" ]; then
        # 1. Sudo access (Idempotent)
        if groups dennis | grep -q '\bsudo\b'; then
            log OK "User dennis is already in the sudo group."
        else
            usermod -aG sudo dennis
            log OK "Added dennis to the sudo group."
        fi

        # 2. Add course-provided SSH key (Idempotent)
        if ! grep -qF "$DENNIS_KEY" "$AUTHORIZED_KEYS"; then
            echo "$DENNIS_KEY" >> "$AUTHORIZED_KEYS"
            log OK "Added required external SSH key to dennis."
        else
            log OK "Required external SSH key for dennis verified."
        fi
    fi
done

log SUCCESS "Assignment2 configuration complete. The server is fully configured."
