#!/bin/bash
# This script runs the configure-host.sh script from the current directory
# to modify 2 servers and update the local /etc/hosts file

VERBOSE=false
EXTRA_ARGS=""

if [ "$1" = "-verbose" ]; then
    VERBOSE=true
    EXTRA_ARGS="-verbose"
fi

vlog() {
    if [ "$VERBOSE" = true ]; then
        echo "$@"
    fi
}

# Ensure configure-host.sh exists and is executable
if [ ! -x ./configure-host.sh ]; then
    echo "Error: ./configure-host.sh not found or not executable" >&2
    exit 1
fi

# ---- Server1: copy and run ----
vlog "Copying configure-host.sh to server1-mgmt..."
scp ./configure-host.sh remoteadmin@server1-mgmt:/root
if [ $? -ne 0 ]; then
    echo "Error: failed to copy configure-host.sh to server1-mgmt" >&2
    exit 1
fi

vlog "Running configure-host.sh on server1-mgmt..."
ssh remoteadmin@server1-mgmt -- /root/configure-host.sh $EXTRA_ARGS -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4
if [ $? -ne 0 ]; then
    echo "Error: remote configuration failed on server1-mgmt" >&2
    exit 1
fi

# ---- Server2: copy and run ----
vlog "Copying configure-host.sh to server2-mgmt..."
scp ./configure-host.sh remoteadmin@server2-mgmt:/root
if [ $? -ne 0 ]; then
    echo "Error: failed to copy configure-host.sh to server2-mgmt" >&2
    exit 1
fi

vlog "Running configure-host.sh on server2-mgmt..."
ssh remoteadmin@server2-mgmt -- /root/configure-host.sh $EXTRA_ARGS -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3
if [ $? -ne 0 ]; then
    echo "Error: remote configuration failed on server2-mgmt" >&2
    exit 1
fi

# ---- Update local /etc/hosts ----
vlog "Updating local /etc/hosts for loghost..."
sudo ./configure-host.sh $EXTRA_ARGS -hostentry loghost 192.168.16.3
if [ $? -ne 0 ]; then
    echo "Error: failed to update local hosts entry for loghost" >&2
    exit 1
fi

vlog "Updating local /etc/hosts for webhost..."
sudo ./configure-host.sh $EXTRA_ARGS -hostentry webhost 192.168.16.4
if [ $? -ne 0 ]; then
    echo "Error: failed to update local hosts entry for webhost" >&2
    exit 1
fi

ssh-keyscan server1-mgmt >> ~/.ssh/known_hosts

vlog "lab3.sh completed successfully."
exit 0
