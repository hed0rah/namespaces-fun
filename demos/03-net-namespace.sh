#!/usr/bin/env bash
# =============================================================================
# Network Namespace - "Building a network from nothing"
# =============================================================================
# Net namespaces give you a completely blank network stack.
# We'll create a veth pair to connect the namespace to the host,
# assign IPs, and ping between them. This is what Docker does.
#
# Run: sudo ./03-net-namespace.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'
NS_NAME="demo-netns"

cleanup() {
    echo -e "\n${CYAN}[*] Cleaning up...${RESET}"
    ip netns del "$NS_NAME" 2>/dev/null || true
    ip link del veth-host 2>/dev/null || true
    echo -e "${GREEN}[*] Clean.${RESET}"
}
trap cleanup EXIT

echo -e "${CYAN}=== Network Namespace ===${RESET}"
echo ""

# Step 1: Create a named network namespace
echo -e "${CYAN}[1] Creating network namespace '${NS_NAME}'...${RESET}"
ip netns add "$NS_NAME"
echo -e "${GREEN}    Done. Current namespaces:${RESET}"
ip netns list
echo ""

# Step 2: Show it starts with NOTHING
echo -e "${CYAN}[2] What does the namespace see? Nothing but loopback:${RESET}"
ip netns exec "$NS_NAME" ip link show
echo ""

# Step 3: Create a veth pair (virtual ethernet cable)
echo -e "${CYAN}[3] Creating a veth pair (virtual cable between host and namespace)...${RESET}"
ip link add veth-host type veth peer name veth-ns
echo -e "${GREEN}    Created: veth-host <====cable====> veth-ns${RESET}"
echo ""

# Step 4: Move one end into the namespace
echo -e "${CYAN}[4] Moving veth-ns into the namespace...${RESET}"
ip link set veth-ns netns "$NS_NAME"
echo -e "${GREEN}    veth-ns has vanished from host (it's in the namespace now)${RESET}"
echo ""
echo -e "    Host interfaces:"
ip -br link show | grep -E 'veth|lo' | sed 's/^/      /'
echo -e "    Namespace interfaces:"
ip netns exec "$NS_NAME" ip -br link show | sed 's/^/      /'
echo ""

# Step 5: Assign IPs
echo -e "${CYAN}[5] Assigning IPs...${RESET}"
ip addr add 10.200.1.1/24 dev veth-host
ip link set veth-host up

ip netns exec "$NS_NAME" ip addr add 10.200.1.2/24 dev veth-ns
ip netns exec "$NS_NAME" ip link set veth-ns up
ip netns exec "$NS_NAME" ip link set lo up

echo -e "${GREEN}    Host:      veth-host = 10.200.1.1${RESET}"
echo -e "${GREEN}    Namespace: veth-ns   = 10.200.1.2${RESET}"
echo ""

# Step 6: Ping!
echo -e "${CYAN}[6] Pinging the namespace from the host...${RESET}"
ping -c 2 -W 1 10.200.1.2 | sed 's/^/    /'
echo ""

echo -e "${CYAN}[7] Pinging the host from inside the namespace...${RESET}"
ip netns exec "$NS_NAME" ping -c 2 -W 1 10.200.1.1 | sed 's/^/    /'
echo ""

echo -e "${YELLOW}=== Key insight ===${RESET}"
echo -e "  The namespace started with ZERO network connectivity."
echo -e "  We built a point-to-point link from scratch."
echo -e "  Docker/podman do exactly this, plus iptables NAT for internet access."
echo -e "  Run 'sudo ip netns exec ${NS_NAME} bash' to poke around before cleanup."
