#!/bin/bash

# --- CRON FIX: SET PATH ---
# This line is critical. It tells cron where to find commands like 'route', 'arp', and 'system_profiler'
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
# --------------------------

# --- CONFIGURATION ---
HA_WEBHOOK_URL="http://homeassistant.local:8123/api/webhook/macbook_power_updates"

# SPACE-SEPARATED LIST of all your Router MAC addresses
ALLOWED_MACS="1c:b:8b:40:37:5 84:78:48:f0:12:3c 60:22:32:3b:37:94"
# ---------------------

# 1. Check for External Displays
display_count=$(system_profiler SPDisplaysDataType | grep -c "Display Type")

# 2. Check Location (via Router MAC)
current_gateway_ip=$(route -n get default | awk '/gateway/ {print $2}')
if [ -n "$current_gateway_ip" ]; then
    current_gateway_mac=$(arp -n "$current_gateway_ip" | awk '{print $4}')
else
    current_gateway_mac="unknown"
fi

# 3. Get Real Power Usage (SystemPowerIn)
raw_watts=$(ioreg -rw0 -c AppleSmartBattery | grep -o '"SystemPowerIn"=[0-9]*' | cut -d'=' -f2)

if [ -z "$raw_watts" ]; then
    watts=0
else
    # Convert milliwatts to Watts
    watts=$(echo $raw_watts | awk '{print $1/1000}')
fi

# --- LOGIC ENGINE ---

# Condition A: If External Display is connected (Count > 1)
if [ "$display_count" -gt 1 ]; then
    watts=0
fi

# Condition B: If Current MAC is NOT in the Allowed List
# We check if the ALLOWED_MACS string contains the current_gateway_mac
if [[ "$ALLOWED_MACS" != *"$current_gateway_mac"* ]]; then
    watts=0
fi

# 4. Send to Home Assistant (Silent Mode)
curl -X POST -H "Content-Type: application/json" -d "{\"power\": $watts}" $HA_WEBHOOK_URL >/dev/null 2>&1
