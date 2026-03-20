#!/usr/bin/env bash
# =============================================================================
# Namespace Snooping - "Peeking behind the curtain"
# =============================================================================
# This script shows how to inspect, compare, and enter existing namespaces.
# Great for debugging containers and understanding what's REALLY happening
# on a system running Docker/podman/k8s.
#
# Run: sudo ./08-namespace-snoop.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

echo -e "${BOLD}${CYAN}=== Namespace Snooping ===${RESET}"
echo -e "${YELLOW}    Everything is a file. Namespaces are in /proc/<pid>/ns/${RESET}"
echo ""

# --- Show our own namespaces ---
echo -e "${CYAN}[1] Our namespaces (PID $$):${RESET}"
ls -la /proc/$$/ns/ | tail -n +2 | sed 's/^/    /'
echo ""

echo -e "${CYAN}[2] Each namespace is an inode. Same inode = same namespace.${RESET}"
echo -e "    Let's compare PID 1 (init) with ourselves:"
echo ""
printf "    %-10s %-25s %-25s %s\n" "TYPE" "PID 1 (init)" "PID $$ (us)" "SAME?"
printf "    %-10s %-25s %-25s %s\n" "----" "------------" "-----------" "-----"

for ns in /proc/$$/ns/*; do
    ns_type=$(basename "$ns")
    our_ns=$(readlink "$ns" 2>/dev/null || echo "?")
    init_ns=$(readlink "/proc/1/ns/$ns_type" 2>/dev/null || echo "?")
    if [[ "$our_ns" == "$init_ns" ]]; then
        same="${GREEN}YES${RESET}"
    else
        same="${RED}NO${RESET}"
    fi
    printf "    %-10s %-25s %-25s %b\n" "$ns_type" "$init_ns" "$our_ns" "$same"
done
echo ""

# --- Find processes in different namespaces ---
echo -e "${CYAN}[3] Finding processes in non-default namespaces...${RESET}"
echo -e "    (These are likely containers, sandboxes, or isolated processes)"
echo ""

INIT_PID_NS=$(readlink /proc/1/ns/pid 2>/dev/null)
found=0
for pid_dir in /proc/[0-9]*/; do
    pid=$(basename "$pid_dir")
    pid_ns=$(readlink "${pid_dir}ns/pid" 2>/dev/null || continue)
    if [[ "$pid_ns" != "$INIT_PID_NS" ]]; then
        cmdline=$(tr '\0' ' ' < "${pid_dir}cmdline" 2>/dev/null | head -c 60)
        printf "    PID %-8s ns=%-20s cmd=%s\n" "$pid" "$pid_ns" "$cmdline"
        found=$((found + 1))
        [[ $found -ge 15 ]] && { echo "    ... (truncated)"; break; }
    fi
done
[[ $found -eq 0 ]] && echo -e "    ${YELLOW}None found. Try running a Docker container first!${RESET}"
echo ""

# --- nsenter ---
echo -e "${CYAN}[4] nsenter - entering another process's namespace${RESET}"
echo -e "    Let's create a namespace and then enter it from outside."
echo ""

# Create a long-lived process in a new UTS namespace
unshare --uts -- bash -c 'hostname sneaky-namespace; sleep 30' &
CHILD_PID=$!
sleep 0.5

echo -e "    Created process ${GREEN}${CHILD_PID}${RESET} in its own UTS namespace"
echo -e "    Its hostname: $(nsenter --target $CHILD_PID --uts hostname)"
echo -e "    Our hostname: $(hostname)"
echo ""

echo -e "${CYAN}[5] Using nsenter to run a command in that namespace:${RESET}"
echo -e "    $ nsenter --target $CHILD_PID --uts -- hostname"
echo -e "    $(nsenter --target $CHILD_PID --uts -- hostname)"
echo ""

kill $CHILD_PID 2>/dev/null; wait $CHILD_PID 2>/dev/null || true

# --- /proc/pid/ns is the window into everything ---
echo -e "${YELLOW}=== Key tools ===${RESET}"
echo -e "  ${GREEN}ls -la /proc/<pid>/ns/${RESET}   - see a process's namespaces"
echo -e "  ${GREEN}readlink /proc/<pid>/ns/X${RESET} - get namespace inode for comparison"
echo -e "  ${GREEN}nsenter --target <pid>${RESET}    - enter a process's namespace(s)"
echo -e "  ${GREEN}lsns${RESET}                      - list all namespaces on the system"
echo ""

echo -e "${CYAN}[bonus] lsns output:${RESET}"
lsns 2>/dev/null | head -20 | sed 's/^/    /' || echo -e "    ${YELLOW}lsns not available${RESET}"
