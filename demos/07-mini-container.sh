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
# Note: cgroup.controllers is a FILE, not a directory, so test with -f.
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    # cgroups v2
    mkdir -p "$CGROUP_PATH"
    echo "52428800" > "$CGROUP_PATH/memory.max" 2>/dev/null || echo -e "${YELLOW}    (cgroup memory limit skipped - may need permissions)${RESET}"
    echo -e "${GREEN}    cgroup v2: ${CGROUP_PATH}${RESET}"
else
    echo -e "${YELLOW}    (skipping cgroup setup - v1 or not available)${RESET}"
    CGROUP_PATH=""
fi
echo ""

# Install cleanup trap NOW, before any code path that might exit non-zero.
cleanup() {
    if [[ -n "${CGROUP_PATH:-}" ]] && [[ -d "${CGROUP_PATH:-}" ]]; then
        rmdir "$CGROUP_PATH" 2>/dev/null || true
    fi
    umount "$ROOTFS/proc" 2>/dev/null || true
    umount "$ROOTFS/sys" 2>/dev/null || true
    umount "$ROOTFS/dev" 2>/dev/null || true
    umount "$ROOTFS" 2>/dev/null || true
}
trap cleanup EXIT

# --- Step 1b: If the rootfs has no real shell binary, install a static busybox.
# Note: any /bin/sh symlink in the rootfs likely points to /bin/busybox using an
# absolute path, which on the HOST resolves to the HOST's busybox. We need a
# rootfs-internal shell binary, so check for that directly.
if [[ ! -f "$ROOTFS/bin/bash" ]] && [[ ! -f "$ROOTFS/bin/busybox" ]]; then
    echo -e "${CYAN}[1b] Setting up busybox in the rootfs...${RESET}"

    # Find a usable static busybox. Order: host /usr/bin/busybox, then existing
    # $ROOTFS/busybox if its architecture matches the kernel.
    # Normalise both directions: uname says x86_64, file(1) says x86-64.
    HOST_ARCH=$(uname -m)
    arch_match() { file -L "$1" 2>/dev/null | tr '_' '-' | grep -q "$(echo "$HOST_ARCH" | tr '_' '-')"; }
    BB_SOURCE=""
    for cand in /usr/bin/busybox /bin/busybox; do
        if [[ -x "$cand" ]] && arch_match "$cand"; then
            BB_SOURCE="$cand"
            break
        fi
    done
    if [[ -z "$BB_SOURCE" ]] && [[ -x "$ROOTFS/busybox" ]]; then
        if arch_match "$ROOTFS/busybox"; then
            BB_SOURCE="$ROOTFS/busybox"
        else
            echo -e "${YELLOW}    ${ROOTFS}/busybox is the wrong architecture for this host (${HOST_ARCH}).${RESET}"
        fi
    fi

    if [[ -z "$BB_SOURCE" ]]; then
        echo -e "${RED}[!] No usable static busybox found.${RESET}"
        echo -e "${YELLOW}    Install one with: ${GREEN}sudo apt install busybox-static${YELLOW} (Debian/Ubuntu)${RESET}"
        echo -e "${YELLOW}    or download from: ${GREEN}https://busybox.net/downloads/binaries/${RESET}"
        exit 1
    fi

    mkdir -p "$ROOTFS/bin" "$ROOTFS/sbin" "$ROOTFS/usr/bin" "$ROOTFS/usr/sbin" "$ROOTFS/etc" "$ROOTFS/root"
    cp "$BB_SOURCE" "$ROOTFS/bin/busybox"
    chmod +x "$ROOTFS/bin/busybox"
    # Install applet symlinks (sh, ls, ps, mount, hostname, etc.).
    # Skip "busybox" itself - that's the binary, not a symlink target.
    for applet in $("$ROOTFS/bin/busybox" --list 2>/dev/null); do
        [[ "$applet" == "busybox" ]] && continue
        ln -sf /bin/busybox "$ROOTFS/bin/$applet" 2>/dev/null || true
    done
    echo -e "${GREEN}    Installed static busybox (${BB_SOURCE}) to ${ROOTFS}/bin/${RESET}"

    # Minimal /etc/passwd and /etc/group so whoami/id can resolve uid 0.
    [[ -f "$ROOTFS/etc/passwd" ]] || echo "root:x:0:0:root:/root:/bin/sh" > "$ROOTFS/etc/passwd"
    [[ -f "$ROOTFS/etc/group"  ]] || echo "root:x:0:" > "$ROOTFS/etc/group"
    echo ""
fi

# --- Step 2: Prepare mounts inside rootfs ---
echo -e "${CYAN}[2] Preparing container filesystem...${RESET}"
mkdir -p "$ROOTFS"/{proc,sys,dev,tmp}
echo ""

# --- Step 3: LAUNCH THE CONTAINER ---
echo -e "${CYAN}[3] Launching container with ALL namespace types...${RESET}"
echo -e "    Namespaces: ${GREEN}pid + uts + mount + ipc + net + cgroup${RESET}"
echo -e "    Root:       ${GREEN}${ROOTFS}${RESET}"
echo -e "    Hostname:   ${GREEN}${CONTAINER_HOSTNAME}${RESET}"
echo ""
echo -e "${BOLD}${YELLOW}    === Dropping you into the container shell === ${RESET}"
echo -e "${YELLOW}    Type 'exit' to leave. Try: hostname, ps aux, id, mount${RESET}"
echo ""

# The big unshare - this is basically what runc does (in Go).
# We run as real root (sudo) and skip --user; mixing user namespaces with
# pivot_root onto a host-owned rootfs needs subuid/newuidmap setup that's
# beyond a single-script demo. See the user namespace demo (05) for that side.
#
# Subshell trick: put ourselves into the cgroup BEFORE exec'ing unshare,
# so the container (and its descendants) inherit cgroup membership.
(
    if [[ -n "${CGROUP_PATH:-}" ]] && [[ -w "$CGROUP_PATH/cgroup.procs" ]]; then
        echo $BASHPID > "$CGROUP_PATH/cgroup.procs" 2>/dev/null || true
    fi
    # Inner script uses positional args ($1=hostname, $2=rootfs) so we can
    # keep it single-quoted and let $$, $(...), etc. expand INSIDE the
    # unshared shell (after pivot_root) rather than in the outer shell.
    exec unshare \
        --pid \
        --uts \
        --mount \
        --ipc \
        --net \
        --cgroup \
        --fork \
        -- bash -c '
            HOST="$1"
            ROOTFS_PATH="$2"

            hostname "$HOST"

            # Make root rprivate so our mounts dont propagate to the host.
            mount --make-rprivate /

            # pivot_root requires new_root to be a mount point distinct from /.
            # Bind-mount the rootfs onto itself to satisfy that.
            mount --bind "$ROOTFS_PATH" "$ROOTFS_PATH"

            # Mount proc/sys/dev inside the rootfs
            mount -t proc proc "$ROOTFS_PATH/proc"
            mount -t sysfs sys "$ROOTFS_PATH/sys"
            mount --bind /dev "$ROOTFS_PATH/dev"

            # pivot_root: swap / for the rootfs, then unmount the old root
            cd "$ROOTFS_PATH"
            mkdir -p .old_root
            pivot_root . .old_root
            umount -l /.old_root 2>/dev/null || true
            rmdir /.old_root 2>/dev/null || true

            # Minimal environment
            export HOME=/root
            export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
            export PS1="$HOST# "
            export TERM=xterm

            # Bash caches command paths; clear it after pivot_root so PATH lookup is fresh.
            hash -r

            echo ""
            echo -e "\033[0;32m  [container] Hostname: $(hostname)\033[0m"
            echo -e "\033[0;32m  [container] PID:      $$\033[0m"
            echo -e "\033[0;32m  [container] User:     $(whoami) (uid=$(id -u))\033[0m"
            echo -e "\033[0;32m  [container] Root:     /\033[0m"
            echo ""

            # Pick whatever shell the rootfs actually has
            if [ -x /bin/bash ]; then
                exec /bin/bash --norc
            elif [ -x /bin/sh ]; then
                exec /bin/sh
            elif [ -x /bin/busybox ]; then
                exec /bin/busybox sh
            else
                echo "no shell available in rootfs"
                exit 1
            fi
        ' bash "$CONTAINER_HOSTNAME" "$ROOTFS"
)

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
