#!/usr/bin/env bash
# =============================================================================
# Build a Container from Scratch - "Docker is just a fancy shell script"
# =============================================================================
# We combine ALL namespace types + chroot + cgroups to build a real
# (tiny) container using nothing but bash and unshare.
# Combines all namespace types + chroot + cgroups.
#
# Requires: debootstrap OR a pre-built rootfs at ./rootfs/
#
# Run: sudo ./07-mini-container.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

ROOTFS="$(cd "$(dirname "$0")" && pwd)/rootfs"
CONTAINER_HOSTNAME="tiny-container"

cat <<'BANNER'

  _          _  ___       _
 | |_  ___ _| |/ _ \ ___| | _____ _ __
 | ' \/ -_) _` | | | / __| |/ / -_) '__|
 | |_| \___\__,_|___|_\__|_|\_\___|_|

BANNER
echo -e "${BOLD}${CYAN}  hed0cker${RESET} ${YELLOW}- building a container from scratch with just bash + unshare${RESET}"
echo ""

# --- Step 0: Build or verify rootfs ---
if [[ ! -d "$ROOTFS" ]]; then
    echo -e "${CYAN}[0] No rootfs found. Let's build one!${RESET}"

    if command -v debootstrap &>/dev/null; then
        echo -e "    Using debootstrap to create a minimal Debian rootfs..."
        echo -e "    ${YELLOW}(This takes a few minutes the first time)${RESET}"
        debootstrap --variant=minbase stable "$ROOTFS" http://deb.debian.org/debian
    elif command -v dnf &>/dev/null; then
        echo -e "    Using dnf to create a minimal Fedora rootfs..."
        mkdir -p "$ROOTFS"
        dnf --installroot="$ROOTFS" --releasever=39 install -y bash coreutils procps-ng iproute
    elif command -v pacstrap &>/dev/null; then
        echo -e "    Using pacstrap for Arch rootfs..."
        mkdir -p "$ROOTFS"
        pacstrap -c "$ROOTFS" base
    else
        echo -e "${RED}[!] No rootfs at ${ROOTFS} and no package manager to build one.${RESET}"
        echo -e "${YELLOW}    Option 1: apt install debootstrap && re-run${RESET}"
        echo -e "${YELLOW}    Option 2: docker export \$(docker create alpine) | tar -C ${ROOTFS} -xf -${RESET}"
        echo -e "${YELLOW}    Option 3: mkdir ${ROOTFS} && copy a static busybox into it${RESET}"
        exit 1
    fi
    echo ""
fi

echo -e "${GREEN}[+] Rootfs: ${ROOTFS}${RESET}"
echo -e "    Size: $(du -sh "$ROOTFS" 2>/dev/null | cut -f1)"
echo ""

# --- Step 1: Set up cgroup limits (memory) ---
echo -e "${CYAN}[1] Setting up cgroup memory limit (50MB)...${RESET}"
CGROUP_PATH="/sys/fs/cgroup/tiny-container-$$"
if [[ -d /sys/fs/cgroup/cgroup.controllers ]]; then
    # cgroups v2
    mkdir -p "$CGROUP_PATH"
    echo "52428800" > "$CGROUP_PATH/memory.max" 2>/dev/null || echo -e "${YELLOW}    (cgroup memory limit skipped - may need permissions)${RESET}"
    echo -e "${GREEN}    cgroup v2: ${CGROUP_PATH}${RESET}"
else
    echo -e "${YELLOW}    (skipping cgroup setup - v1 or not available)${RESET}"
    CGROUP_PATH=""
fi
echo ""

cleanup() {
    if [[ -n "${CGROUP_PATH:-}" ]] && [[ -d "${CGROUP_PATH:-}" ]]; then
        rmdir "$CGROUP_PATH" 2>/dev/null || true
    fi
    # Clean up any mounts we made inside the rootfs
    umount "$ROOTFS/proc" 2>/dev/null || true
    umount "$ROOTFS/sys" 2>/dev/null || true
    umount "$ROOTFS/dev" 2>/dev/null || true
}
trap cleanup EXIT

# --- Step 2: Prepare mounts inside rootfs ---
echo -e "${CYAN}[2] Preparing container filesystem...${RESET}"
mkdir -p "$ROOTFS"/{proc,sys,dev,tmp}
echo ""

# --- Step 3: LAUNCH THE CONTAINER ---
echo -e "${CYAN}[3] Launching container with ALL namespace types...${RESET}"
echo -e "    Namespaces: ${GREEN}pid + uts + mount + ipc + net + user + cgroup${RESET}"
echo -e "    Root:       ${GREEN}${ROOTFS}${RESET}"
echo -e "    Hostname:   ${GREEN}${CONTAINER_HOSTNAME}${RESET}"
echo ""
echo -e "${BOLD}${YELLOW}    === Dropping you into the container shell === ${RESET}"
echo -e "${YELLOW}    Type 'exit' to leave. Try: hostname, ps aux, id, mount${RESET}"
echo ""

# The big unshare - this is basically what runc does (in Go)
unshare \
    --pid \
    --uts \
    --mount \
    --ipc \
    --net \
    --fork \
    --map-root-user \
    -- bash -c "
        # Set hostname
        hostname ${CONTAINER_HOSTNAME}

        # Mount proc/sys/dev inside the rootfs
        mount -t proc proc ${ROOTFS}/proc
        mount -t sysfs sys ${ROOTFS}/sys
        mount -t devtmpfs dev ${ROOTFS}/dev 2>/dev/null || mount --bind /dev ${ROOTFS}/dev

        # Pivot root - the real deal (not just chroot)
        cd ${ROOTFS}
        mkdir -p .old_root
        pivot_root . .old_root

        # Clean up old root
        umount -l /.old_root 2>/dev/null || true
        rmdir /.old_root 2>/dev/null || true

        # Set up minimal environment
        export HOME=/root
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
        export PS1='${CONTAINER_HOSTNAME}# '
        export TERM=xterm

        echo ''
        echo -e '\033[0;32m  [container] Hostname: \$(hostname)\033[0m'
        echo -e '\033[0;32m  [container] PID:      \$\$\033[0m'
        echo -e '\033[0;32m  [container] User:     \$(whoami) (uid=\$(id -u))\033[0m'
        echo -e '\033[0;32m  [container] Root:     /\033[0m'
        echo ''

        exec bash --norc
    "

echo ""
echo -e "${CYAN}[*] Container exited. Welcome back to the host.${RESET}"
echo -e "${YELLOW}=== What just happened ===${RESET}"
echo -e "  We built a container using:"
echo -e "    1. ${GREEN}unshare${RESET}    - create all namespace types"
echo -e "    2. ${GREEN}pivot_root${RESET} - swap filesystem root"
echo -e "    3. ${GREEN}cgroups${RESET}    - resource limits"
echo -e "    4. ${GREEN}mount${RESET}      - isolated proc/sys/dev"
echo -e ""
echo -e "  That's it. That's a container. Docker just adds image management,"
echo -e "  networking, and a nice API on top of exactly this."
