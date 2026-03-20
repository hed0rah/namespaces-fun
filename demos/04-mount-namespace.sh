#!/usr/bin/env bash
# =============================================================================
# Mount Namespace - "Your filesystem is a lie"
# =============================================================================
# Mount namespaces let you create isolated filesystem views.
# We'll create a tmpfs mount visible ONLY inside the namespace.
# The host never sees it. This is how containers get their own /tmp, etc.
#
# Run: sudo ./04-mount-namespace.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'
SECRET_DIR="/tmp/ns-demo-secret"

cleanup() {
    rm -rf "$SECRET_DIR" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$SECRET_DIR"

echo -e "${CYAN}=== Mount Namespace ===${RESET}"
echo ""

echo -e "${CYAN}[1] Creating ${SECRET_DIR} on the host with a file...${RESET}"
echo "HOST_WAS_HERE" > "${SECRET_DIR}/host-file.txt"
ls -la "${SECRET_DIR}/"
echo ""

echo -e "${CYAN}[2] Entering mount namespace and overlaying a tmpfs on that directory...${RESET}"
echo -e "${YELLOW}    The host's files will be hidden (but NOT deleted) by the tmpfs.${RESET}"
echo ""

unshare --mount -- bash -c '
    # Mount a fresh tmpfs over the directory - hides host contents
    mount -t tmpfs tmpfs '"${SECRET_DIR}"'

    echo -e "\033[0;32m  [inside]  Contents of '"${SECRET_DIR}"' (should be empty - tmpfs overlay):\033[0m"
    ls -la '"${SECRET_DIR}"'/
    echo ""

    echo -e "\033[0;36m  [inside]  Writing a secret file only visible in this namespace...\033[0m"
    echo "NAMESPACE_SECRET_$(date +%s)" > '"${SECRET_DIR}"'/namespace-only.txt
    cat '"${SECRET_DIR}"'/namespace-only.txt
    echo ""

    echo -e "\033[0;36m  [inside]  Mount table (filtered):\033[0m"
    mount | grep ns-demo | sed "s/^/    /"
'

echo ""
echo -e "${CYAN}[3] Back on the host. What does ${SECRET_DIR} contain?${RESET}"
ls -la "${SECRET_DIR}/"
echo ""
echo -e "${GREEN}    The host file is still there. The namespace file is gone.${RESET}"
echo -e "${GREEN}    Neither side ever saw the other's version.${RESET}"
echo ""
echo -e "${YELLOW}=== Key insight ===${RESET}"
echo -e "  Mount namespaces are how containers get isolated /proc, /sys, /dev, /tmp."
echo -e "  pivot_root + mount ns = completely different filesystem tree."
