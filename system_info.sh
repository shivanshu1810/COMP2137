#!/bin/bash

echo "Hostname: $(hostname)"

echo "IP Address: $(hostname -I | awk '{print $1}')"

echo "Gateway IP: $(ip route | grep default | awk '{print $3}')"
