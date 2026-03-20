#!/usr/bin/env bash
# =============================================================================
# User Namespace - "I'm root! (not really)"
# =============================================================================
# User namespaces let an unprivileged user MAP themselves to UID 0 (root)
# inside the namespace. They're "root" in there but nobody on the host.
# This is the foundation of rootless containers (podman, etc).
#
# Run as REGULAR USER (no sudo!): ./05-user-namespace.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'

echo -e "${CYAN}=== User Namespace ===${RESET}"
echo -e "Outside: uid=$(id -u) gid=$(id -g) user=$(whoami)"
echo ""

# Check if user namespaces are allowed
if [[ -f /proc/sys/kernel/unprivileged_userns_clone ]] && \
   [[ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" == "0" ]]; then
    echo -e "${RED}[!] Unprivileged user namespaces are disabled on this kernel.${RESET}"
    echo -e "${RED}    Enable with: sudo sysctl kernel.unprivileged_userns_clone=1${RESET}"
    exit 1
fi

echo -e "${CYAN}[*] Entering user namespace, mapping ourselves to root...${RESET}"
echo ""

# --user: new user namespace
# --map-root-user: map current UID/GID to 0/0 inside
unshare --user --map-root-user -- bash -c '
    echo -e "\033[0;32m  [inside]  uid=$(id -u) gid=$(id -g) user=$(whoami)\033[0m"
    echo -e "\033[0;32m  [inside]  I AM ROOT! ...inside this namespace.\033[0m"
    echo ""

    echo -e "\033[0;36m  [inside]  UID map (/proc/self/uid_map):\033[0m"
    cat /proc/self/uid_map | sed "s/^/    /"
    echo ""

    echo -e "\033[0;36m  [inside]  GID map (/proc/self/gid_map):\033[0m"
    cat /proc/self/gid_map | sed "s/^/    /"
    echo ""

    echo -e "\033[0;36m  [inside]  Can I read /etc/shadow? (the real test of power)\033[0m"
    if cat /etc/shadow > /dev/null 2>&1; then
        echo -e "\033[0;31m    Yes! (this is unexpected)\033[0m"
    else
        echo -e "\033[0;32m    Nope! Permission denied. Im fake root.\033[0m"
    fi
    echo ""

    echo -e "\033[0;36m  [inside]  Can I create files owned by root?\033[0m"
    TMPF=$(mktemp)
    ls -la "$TMPF" | sed "s/^/    /"
    echo -e "\033[0;32m    Looks like root owns it... but only from in here.\033[0m"
    rm -f "$TMPF"
'

echo ""
echo -e "${CYAN}[*] Back outside. Still: uid=$(id -u) user=$(whoami)${RESET}"
echo ""
echo -e "${YELLOW}=== Key insight ===${RESET}"
echo -e "  User namespaces are the magic behind rootless containers."
echo -e "  You get UID 0 powers inside the namespace (create devices, mount, etc)"
echo -e "  but on the host you're still just $(whoami). The kernel maps UIDs."
echo -e "  No sudo was used in any of this."
