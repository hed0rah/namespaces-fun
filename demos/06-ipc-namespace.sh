#!/usr/bin/env bash
# =============================================================================
# IPC Namespace - "Can you hear me now? No."
# =============================================================================
# IPC namespaces isolate System V IPC objects (message queues, semaphores,
# shared memory). We'll create a message queue on the host, then show
# it's invisible from inside an IPC namespace.
#
# Run: sudo ./06-ipc-namespace.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'

# Check for ipcmk
if ! command -v ipcmk &>/dev/null; then
    echo -e "${RED}[!] 'ipcmk' not found. Install util-linux.${RESET}"
    exit 1
fi

cleanup() {
    if [[ -n "${QUEUE_ID:-}" ]]; then
        ipcrm -q "$QUEUE_ID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo -e "${CYAN}=== IPC Namespace ===${RESET}"
echo ""

# Create a message queue on the host
echo -e "${CYAN}[1] Creating a System V message queue on the host...${RESET}"
QUEUE_ID=$(ipcmk -Q | grep -oP 'id: \K\d+')
echo -e "${GREEN}    Created message queue ID: ${QUEUE_ID}${RESET}"
echo ""

echo -e "${CYAN}[2] Host IPC state:${RESET}"
ipcs -q | sed 's/^/    /'
echo ""

echo -e "${CYAN}[3] Entering IPC namespace - same command, different world...${RESET}"
echo ""

unshare --ipc -- bash -c '
    echo -e "\033[0;32m  [inside]  IPC queues visible:\033[0m"
    ipcs -q | sed "s/^/    /"
    echo ""
    echo -e "\033[0;32m  [inside]  The host queue (ID '"$QUEUE_ID"') is INVISIBLE here.\033[0m"
    echo ""

    echo -e "\033[0;36m  [inside]  Creating our own queue inside the namespace...\033[0m"
    NS_QUEUE=$(ipcmk -Q | grep -oP "id: \K\d+")
    echo -e "\033[0;32m  [inside]  Created queue ID: ${NS_QUEUE}\033[0m"
    ipcs -q | sed "s/^/    /"
    # queue disappears when namespace exits
'

echo ""
echo -e "${CYAN}[4] Back on host. Did the namespace's queue leak out?${RESET}"
ipcs -q | sed 's/^/    /'
echo -e "${GREEN}    Nope. Only our original queue (ID: ${QUEUE_ID}) remains.${RESET}"
echo ""
echo -e "${YELLOW}=== Key insight ===${RESET}"
echo -e "  IPC namespaces prevent cross-container communication via shared memory/"
echo -e "  semaphores/message queues. Without this, containers could signal each other"
echo -e "  through these legacy IPC mechanisms."
