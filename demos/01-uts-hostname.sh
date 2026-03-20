#!/usr/bin/env bash
# =============================================================================
# UTS Namespace - "Who am I?"
# =============================================================================
# The UTS namespace isolates hostname and NIS domain name.
# This is the gentlest intro to namespaces - watch the hostname change
# inside the namespace while the host stays untouched.
#
# Run: sudo ./01-uts-hostname.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; RESET='\033[0m'

echo -e "${CYAN}=== UTS Namespace ===${RESET}"
echo -e "Host hostname: ${GREEN}$(hostname)${RESET}"
echo ""

echo -e "${CYAN}[*] Entering a new UTS namespace with unshare...${RESET}"
echo -e "${CYAN}[*] Setting hostname to 'namespace-land' inside${RESET}"
echo ""

# unshare -u creates a new UTS namespace
# We fork a child that changes hostname, sleeps, then exits
unshare --uts -- bash -c '
    hostname namespace-land
    echo -e "\033[0;32m  [inside]  hostname = $(hostname)\033[0m"
    echo -e "\033[0;32m  [inside]  /proc/sys/kernel/hostname = $(cat /proc/sys/kernel/hostname)\033[0m"
    echo ""
    echo -e "\033[0;36m  [inside]  Sleeping 2s so you can poke around from another terminal...\033[0m"
    echo -e "\033[0;36m  [inside]  Try: sudo ls -la /proc/$$/ns/uts\033[0m"
    sleep 2
'

echo ""
echo -e "Host hostname after: ${GREEN}$(hostname)${RESET}"
echo -e "${CYAN}[*] See? The host hostname was never touched.${RESET}"
