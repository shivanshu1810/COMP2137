#!/bin/bash

# Ignore termination signals
trap '' TERM HUP INT

# Default verbose mode
VERBOSE=false

# Variables that store requested changes
DESIRED_NAME=""
DESIRED_IP=""
HOSTENTRY_NAME=""
HOSTENTRY_IP=""

# Helper for verbose messages
vlog() {
    if $VERBOSE; then
        echo "$@"
    fi
}

# ---------------- Argument Parsing ----------------
while [ $# -gt 0 ]; do
    case "$1" in
        -verbose)
            VERBOSE=true
            shift
            ;;
        -name)
            DESIRED_NAME="$2"
            shift 2
            ;;
        -ip)
            DESIRED_IP="$2"
            shift 2
            ;;
        -hostentry)
            HOSTENTRY_NAME="$2"
            HOSTENTRY_IP="$3"
            shift 3
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done
# ---------------------------------------------------

# Placeholder functions (we fill them later)
set_hostname() {
    # If no -name was provided, do nothing
    if [ -z "$DESIRED_NAME" ]; then
        return 0
    fi

    CURRENT_NAME=$(hostname)

    # If the hostname is already correct
    if [ "$CURRENT_NAME" = "$DESIRED_NAME" ]; then
        vlog "Hostname already set to $DESIRED_NAME"
        return 0
    fi

    # Otherwise, hostname needs to change
    vlog "Changing hostname from $CURRENT_NAME to $DESIRED_NAME"

    # Update /etc/hostname
    if ! echo "$DESIRED_NAME" > /etc/hostname; then
        echo "Error: could not update /etc/hostname" >&2
        exit 1
    fi

    # Update /etc/hosts entry
    if grep -q "[[:space:]]$CURRENT_NAME\$" /etc/hosts; then
        # Replace the name keeping the same IP
        sed -i "s/\([0-9.]\+\s\+\)$CURRENT_NAME/\1$DESIRED_NAME/" /etc/hosts
    else
        # Add new entry if not existing
        echo "127.0.1.1 $DESIRED_NAME" >> /etc/hosts
    fi

    # Apply hostname to running system
    hostname "$DESIRED_NAME"

    # Log the change
    logger -t configure-host "Hostname changed from $CURRENT_NAME to $DESIRED_NAME"
}

set_ip() {
    if [ -z "$DESIRED_IP" ]; then
        return 0
    fi

    LANIF="eth0"
    NETPLAN_FILE="/etc/netplan/10-lxc.yaml"

    # Ensure eth0 exists
    if ! ip link show "$LANIF" >/dev/null 2>&1; then
        echo "Error: Interface $LANIF not found." >&2
        exit 1
    fi

    CURRENT_IP=$(ip -4 addr show "$LANIF" | awk '/inet / {print $2}' | cut -d/ -f1)

    if [ "$CURRENT_IP" = "$DESIRED_IP" ]; then
        vlog "$LANIF already has IP $DESIRED_IP"
        return 0
    fi

    vlog "Changing IP on $LANIF from ${CURRENT_IP:-none} to $DESIRED_IP"

    # Backup
    cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak.$$"

    # Replace ONLY the address under eth0:
    # We search between "eth0:" and the next interface definition
    # and update ONLY the addresses line inside that block.
    # sed -i "/^ *eth0:/,/^[^ ]/{ s/[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+\/24/$DESIRED_IP\/24/ }" "$NETPLAN_FILE"
     sed -i "0,/addresses:/s/addresses: \[[0-9.]\+\/24]/addresses: [$DESIRED_IP\/24]/" "$NETPLAN_FILE"


    # Apply changes
    if ! netplan apply; then
        echo "Error: netplan apply failed." >&2
        cp "$NETPLAN_FILE.bak.$$" "$NETPLAN_FILE"
        exit 1
    fi

    # Fix /etc/hosts for hostname
    HOSTNAME_NOW=$(hostname)

    if grep -q "[[:space:]]$HOSTNAME_NOW\$" /etc/hosts; then
        sed -i "s/^[0-9.]\+[[:space:]]\+$HOSTNAME_NOW\$/$DESIRED_IP $HOSTNAME_NOW/" /etc/hosts
    else
        echo "$DESIRED_IP $HOSTNAME_NOW" >> /etc/hosts
    fi

    logger -t configure-host "IP on $LANIF changed from ${CURRENT_IP:-none} to $DESIRED_IP"
}


set_hostentry() {
    # If -hostentry was not provided, skip
    if [ -z "$HOSTENTRY_NAME" ] || [ -z "$HOSTENTRY_IP" ]; then
        return 0
    fi

    # Does the name already exist in /etc/hosts?
    if grep -q "[[:space:]]$HOSTENTRY_NAME\$" /etc/hosts; then

        # Extract current IP
        CURRENT_ENTRY_IP=$(grep "[[:space:]]$HOSTENTRY_NAME\$" /etc/hosts | awk '{print $1}' | head -n1)

        # If the entry matches exactly, nothing to do
        if [ "$CURRENT_ENTRY_IP" = "$HOSTENTRY_IP" ]; then
            vlog "/etc/hosts already contains: $HOSTENTRY_IP $HOSTENTRY_NAME"
            return 0
        fi

        # Otherwise update the entry
        vlog "Updating /etc/hosts for $HOSTENTRY_NAME from $CURRENT_ENTRY_IP to $HOSTENTRY_IP"
        sed -i "s/^$CURRENT_ENTRY_IP[[:space:]]\+$HOSTENTRY_NAME\$/$HOSTENTRY_IP $HOSTENTRY_NAME/" /etc/hosts
        logger -t configure-host "/etc/hosts entry updated: $HOSTENTRY_NAME from $CURRENT_ENTRY_IP to $HOSTENTRY_IP"

    else
        # Entry does not exist → add a new line
        vlog "Adding new /etc/hosts entry: $HOSTENTRY_IP $HOSTENTRY_NAME"
        echo "$HOSTENTRY_IP $HOSTENTRY_NAME" >> /etc/hosts
        logger -t configure-host "/etc/hosts entry added: $HOSTENTRY_IP $HOSTENTRY_NAME"
    fi
}

# ---------------- Run Features ----------------
set_hostname
set_ip
set_hostentry

exit 0
