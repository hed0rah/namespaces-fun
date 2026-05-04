#!/usr/bin/env bash
# =============================================================================
# Cgroup Namespace - "You can't see my resource limits"
# =============================================================================
# Cgroup namespaces virtualize /proc/self/cgroup so that a container
# sees its cgroup root as "/" instead of the full host path.
# Also shows setting memory + CPU limits.
#
# Run: sudo ./09-cgroup-namespace.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RESET='\033[0m'

CGROUP_NAME="ns-demo-$$"

echo -e "${CYAN}=== Cgroup Namespace ===${RESET}"
echo ""

# Check cgroup version
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    echo -e "${GREEN}    cgroups v2 detected${RESET}"
    CGVER=2
else
    echo -e "${YELLOW}    cgroups v1 detected (some features limited)${RESET}"
    CGVER=1
fi
echo ""

if [[ "$CGVER" -ne 2 ]]; then
    echo -e "${YELLOW}Works best with cgroups v2. Showing basic info only.${RESET}"
    echo ""
    echo -e "${CYAN}Your cgroup:${RESET}"
    cat /proc/self/cgroup | sed 's/^/    /'
    exit 0
fi

CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"

cleanup() {
    # Move ourselves out of the demo cgroup before tearing it down.
    echo $$ > /sys/fs/cgroup/cgroup.procs 2>/dev/null || true
    # Try TERM first, then KILL, polling cgroup.procs until empty (or 5 rounds).
    local round pid
    for round in 1 2 3 4 5; do
        [[ -f "${CGROUP_PATH}/cgroup.procs" ]] || break
        [[ -s "${CGROUP_PATH}/cgroup.procs" ]] || break
        while read -r pid; do
            [[ -z "$pid" || "$pid" == "$$" ]] && continue
            kill "$pid" 2>/dev/null || true
        done < "${CGROUP_PATH}/cgroup.procs"
        sleep 0.3
    done
    if [[ -s "${CGROUP_PATH}/cgroup.procs" ]] 2>/dev/null; then
        while read -r pid; do
            [[ -z "$pid" || "$pid" == "$$" ]] && continue
            kill -9 "$pid" 2>/dev/null || true
        done < "${CGROUP_PATH}/cgroup.procs"
        sleep 0.3
    fi
    rmdir "$CGROUP_PATH" 2>/dev/null || true
}
# Catch all the ways this can end: normal exit, Ctrl+C, SIGTERM from timeout(1).
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Create a cgroup with limits ---
echo -e "${CYAN}[1] Creating cgroup '${CGROUP_NAME}' with resource limits...${RESET}"
mkdir -p "$CGROUP_PATH"

# Memory limit: 64MB
echo "67108864" > "$CGROUP_PATH/memory.max"
# CPU limit: 50% of one core (50ms out of 100ms period)
echo "50000 100000" > "$CGROUP_PATH/cpu.max" 2>/dev/null || true
# PID limit: max 20 processes
echo "20" > "$CGROUP_PATH/pids.max"

echo -e "${GREEN}    Memory limit: $(cat "$CGROUP_PATH/memory.max") bytes (64MB)${RESET}"
echo -e "${GREEN}    CPU limit:    $(cat "$CGROUP_PATH/cpu.max" 2>/dev/null || echo 'N/A')${RESET}"
echo -e "${GREEN}    PID limit:    $(cat "$CGROUP_PATH/pids.max")${RESET}"
echo ""

# --- Show host vs namespaced cgroup view ---
echo -e "${CYAN}[2] Host view of /proc/self/cgroup:${RESET}"
cat /proc/self/cgroup | sed 's/^/    /'
echo ""

echo -e "${CYAN}[3] Now entering cgroup namespace...${RESET}"
echo -e "    The process inside will see '/' as its cgroup root"
echo ""

# Move into the cgroup, then unshare the cgroup namespace
echo $$ > "$CGROUP_PATH/cgroup.procs" 2>/dev/null || true

# We need to use a subshell that's already in the cgroup
bash -c "
    echo \$\$ > ${CGROUP_PATH}/cgroup.procs
    unshare --cgroup -- bash -c '
        echo -e \"\033[0;32m  [inside]  /proc/self/cgroup:\033[0m\"
        cat /proc/self/cgroup | sed \"s/^/    /\"
        echo \"\"
        echo -e \"\033[0;32m  [inside]  See? The cgroup path is now relative - just 0::/\033[0m\"
        echo -e \"\033[0;32m  [inside]  The container thinks it is at the root of the cgroup tree.\033[0m\"
        echo \"\"

        echo -e \"\033[0;36m  [inside]  Trying to spawn 25 procs into a cgroup capped at 20 pids...\033[0m\"
        # & always returns 0 for the foreground shell, so we count the ACTUAL
        # successful forks by re-reading cgroup.procs.
        for i in \$(seq 1 25); do
            sleep 30 & 2>/dev/null
        done 2>/dev/null
        actual=\$(wc -l < ${CGROUP_PATH}/cgroup.procs)
        echo -e \"\033[0;32m  [inside]  Processes alive in this cgroup: \${actual} (cap: 20)\033[0m\"
        echo \"\"
        echo -e \"\033[0;36m  [inside]  Holding for 60s. From another terminal try:\033[0m\"
        echo -e \"\033[0;32m      cat ${CGROUP_PATH}/cgroup.procs        # see member PIDs\033[0m\"
        echo -e \"\033[0;32m      cat ${CGROUP_PATH}/pids.current        # current count\033[0m\"
        echo -e \"\033[0;32m      cat ${CGROUP_PATH}/pids.max            # the limit (20)\033[0m\"
        echo -e \"\033[0;32m      cat ${CGROUP_PATH}/memory.current      # bytes in use\033[0m\"
        echo -e \"\033[0;32m      sudo nsenter --target \$\$ --cgroup cat /proc/self/cgroup\033[0m\"
        echo -e \"\033[0;36m  Press Ctrl+C to clean up early.\033[0m\"
        sleep 60
        kill \$(jobs -p) 2>/dev/null
        wait 2>/dev/null
    '
" 2>/dev/null

echo ""
echo -e "${YELLOW}=== Key insight ===${RESET}"
echo -e "  Cgroup namespaces hide the host's cgroup tree from the container."
echo -e "  Without this, a container could see (and potentially manipulate)"
echo -e "  the cgroup structure of the entire host."
echo -e "  Combined with resource limits, this is how k8s enforces pod limits."
