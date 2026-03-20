#!/usr/bin/env bash
# =============================================================================
# PID Namespace - "Where did all my processes go?"
# =============================================================================
# The PID namespace gives the child its own PID numbering.
# The first process inside gets PID 1 - just like init.
#
# Run: sudo ./02-pid-namespace.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'

echo -e "${CYAN}=== PID Namespace ===${RESET}"
echo -e "Host PID of this script: ${GREEN}$$${RESET}"
echo -e "Host process count:      ${GREEN}$(ls /proc | grep -c '^[0-9]')${RESET}"
echo ""

echo -e "${CYAN}[*] Entering new PID + mount namespace...${RESET}"
echo -e "${YELLOW}    (mount ns needed so we can remount /proc)${RESET}"
echo ""

# --pid --fork: new PID namespace, fork so child is PID 1
# --mount-proc: remount /proc so it reflects the new PID ns
unshare --pid --fork --mount-proc -- bash -c '
    echo -e "\033[0;32m  [inside]  My PID = $$\033[0m"
    echo -e "\033[0;32m  [inside]  I am PID 1! I am init! BOW BEFORE ME!\033[0m"
    echo ""
    echo -e "\033[0;36m  [inside]  Processes visible from inside:\033[0m"
    ps aux
    echo ""
    echo -e "\033[0;36m  [inside]  Only processes in THIS namespace are visible.${RESET}\033[0m"
    echo -e "\033[0;36m  [inside]  The host has hundreds of processes we cannot see.${RESET}\033[0m"
'

echo ""
echo -e "${CYAN}[*] Back on the host. Our PID: ${GREEN}$$${RESET}"
echo -e "Host process count:      ${GREEN}$(ls /proc | grep -c '^[0-9]')${RESET}"
