#!/usr/bash

Hostname=$(hostname)
Username=$(whoami)
DateTime=$(date)

Uptime=$(uptime -p)
CPU=$(lshw -class processor 2>/dev/null | grep 'product:' | head -1 | awk -F: '{print $2}' | xargs)
RAM=$(free -h | awk '/Mem:/ {print $2}')
Disks=$(lshw -short -class disk 2>/dev/null | awk '{print $2, $3, $4, $5}' | column -t)
Video=$(lshw -C display 2>/dev/null | grep 'product:' | awk -F: '{print $2}' | xargs)

GATEWAY=$(ip route | awk '/default/ {print $3}')
HOST_IP=$(ip route get $GATEWAY | grep -oP 'src \K\S+')
DNS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | paste -sd, -)

USERS=$(who | awk '{print $1}' | sort | uniq | paste -sd, -)
DISK_SPACE=$(df -h --output=target,avail | tail -n +2 | awk '{print $1 ": " $2}' | paste -sd, -)
PROC_COUNT=$(ps -e --no-headers | wc -l)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | xargs)
PORTS=$(ss -tuln | awk 'NR>1 {print $5}' | awk -F: '{print $NF}' | sort -u | paste -sd, -)
UFW_STATUS=$(sudo ufw status | head -n 1)
