# Linux Namespaces: From Zero to Container

The kernel primitives behind every container runtime, explained through code.

## What Are Namespaces?

Namespaces are a Linux kernel feature that **partitions kernel resources** so that one set of processes sees one set of resources while another set of processes sees a different set. They're the isolation layer that makes containers work.

Without namespaces, every process on a Linux system shares the same view of:
- Process IDs
- Network interfaces
- Mount points
- Hostnames
- IPC objects
- User/group IDs
- Cgroup hierarchy
- System clocks

Namespaces let you give a process (and its children) their **own private version** of any of these.

## Requirements

- Linux kernel 4.6+ (for all namespace types)
- `util-linux` package (`unshare`, `nsenter`, `lsns`)
- Root access (or a kernel with `unprivileged_userns_clone=1` for user namespaces)

```bash
ls /proc/$$/ns/
```

---

## UTS Namespace

**Isolates:** Hostname and NIS domain name.

The simplest namespace type.

```bash
sudo ./demos/01-uts-hostname.sh
```

**Under the hood:**

1. `unshare --uts` calls `unshare(CLONE_NEWUTS)` syscall
2. The kernel creates a copy of the UTS structure
3. The child process gets the copy; the parent keeps the original
4. `hostname namespace-land` modifies only the copy
5. When the child exits, the copy is destroyed

```bash
# Terminal 1
sudo unshare --uts bash
hostname im-in-a-namespace
hostname  # shows: im-in-a-namespace

# Terminal 2 (on the host)
hostname  # shows: your-real-hostname
```

The host and the namespace have independent hostnames. Neither can see the other's changes.

---

## PID Namespace

**Isolates:** Process ID number space.

```bash
sudo ./demos/02-pid-namespace.sh
```

1. `unshare --pid --fork` creates a new PID namespace
2. The `--fork` is critical: the first **forked** child becomes PID 1 in the new namespace
3. `--mount-proc` remounts `/proc` so tools like `ps` see the new PID space
4. Processes outside the namespace are invisible from inside
5. BUT: the host can still see the namespaced processes (with their host PIDs)

**The PID 1 problem:**
In a PID namespace, if PID 1 dies, ALL processes in that namespace are killed. This is why containers need an init process - it's not optional, it's a kernel requirement.

```bash
# This is why Docker uses --init and why you see /sbin/init or tini in containers
```

A process has TWO PIDs - one in its own namespace and one in the parent:
```bash
# /proc/<host_pid>/status contains NSpid field showing both PIDs
grep NSpid /proc/<pid>/status
```

---

## Network Namespace

**Isolates:** The entire network stack (interfaces, routing tables, iptables rules, sockets).

```bash
sudo ./demos/03-net-namespace.sh
```

1. A new net namespace starts with ONLY a loopback interface (and it's DOWN)
2. We create a **veth pair** - a virtual ethernet cable with two ends
3. One end stays on the host, the other moves into the namespace
4. We assign IPs and bring interfaces up
5. Now the host and namespace can communicate

**This is exactly what Docker does.** Docker's bridge network:
```
Container A ──veth──┐
                    ├── docker0 bridge ── eth0 ── internet
Container B ──veth──┘       (+ iptables NAT)
```

**Adding internet access to a namespace:**
```bash
# Enable IP forwarding on the host
echo 1 > /proc/sys/net/ipv4/ip_forward

# NAT the namespace traffic
iptables -t nat -A POSTROUTING -s 10.200.1.0/24 -j MASQUERADE

# Add a default route inside the namespace
ip netns exec demo-netns ip route add default via 10.200.1.1

# Now the namespace can reach the internet
ip netns exec demo-netns curl ifconfig.me
```

---

## Mount Namespace

**Isolates:** Filesystem mount table.

```bash
sudo ./demos/04-mount-namespace.sh
```

1. `unshare --mount` gives the child a **copy** of the current mount table
2. Any mounts/unmounts inside the namespace only affect the copy
3. We overlay a tmpfs on a directory - the original files are hidden but untouched
4. When the namespace exits, the tmpfs disappears

**This is how containers get their own root filesystem:**
```
pivot_root:
  1. Mount your container rootfs somewhere
  2. Enter a mount namespace
  3. pivot_root swaps / with your new rootfs
  4. Unmount the old root
  5. Now / points to your container image
```

**Mount propagation** - the tricky part. Mounts can be:
- `private` - changes stay in this namespace (default for containers)
- `shared` - changes propagate to peer mounts
- `slave` - receives propagation but doesn't send it
- `unbindable` - can't be bind-mounted

```bash
findmnt -o TARGET,PROPAGATION
```

---

## User Namespace

**Isolates:** User and group IDs, capabilities.

```bash
# No sudo needed
./demos/05-user-namespace.sh
```

**The most important namespace for security.** It allows:
- Unprivileged users to create other namespace types
- UID/GID mapping: be root inside, nobody outside
- Rootless containers (podman's whole thing)

**The UID map:**
```
# /proc/<pid>/uid_map format:
# <id_inside> <id_outside> <range>
         0       1000          1
```
UID 0 inside maps to UID 1000 outside. "Root" in the container is actually your unprivileged user on the host.

```bash
# Without user namespaces, containers need root to:
#   - Mount filesystems
#   - Change hostname
#   - Create network interfaces
#   - Change UIDs

# With user namespaces, you can do ALL of this unprivileged
# because the kernel checks capabilities WITHIN the namespace
```

---

## All Together: Container From Scratch

```bash
sudo ./demos/07-mini-container.sh
```

Combines everything into a working container using only bash:

1. **PID namespace** - isolated process tree
2. **UTS namespace** - custom hostname
3. **Mount namespace** - isolated filesystem
4. **IPC namespace** - isolated IPC objects
5. **Network namespace** - blank network stack
6. **User namespace** - UID mapping
7. **pivot_root** - completely new root filesystem
8. **cgroups** - resource limits

**This is fundamentally what Docker, podman, and containerd do.** The rest is image management, networking plugins, and API/UX.

---

## Debugging Namespaces in Production

### Finding container namespaces
```bash
PID=$(docker inspect -f '{{.State.Pid}}' mycontainer)
ls -la /proc/$PID/ns/

# Enter a container without docker exec (useful when the daemon is stuck)
sudo nsenter --target $PID --all bash
```

### Debugging network issues
```bash
# See what network namespace a process is in
sudo ls -la /proc/$(pidof nginx)/ns/net

# List all network namespaces
sudo lsns -t net

# Enter a container's network namespace
sudo nsenter --target $PID --net bash
# Now run tcpdump, ip addr, iptables, ss, etc.
```

### More inspection tools
```bash
sudo ./demos/08-namespace-snoop.sh
```

---

## How Docker/containerd Actually Does It

Simplified flow of `docker run`:

```
1.  docker CLI → dockerd (API call)
2.  dockerd → containerd (gRPC: create container)
3.  containerd → runc (OCI runtime)
4.  runc:
    a. clone(CLONE_NEWPID | CLONE_NEWUTS | CLONE_NEWNS | ...)
    b. In child:
       - Set up cgroups
       - Mount /proc, /sys, /dev
       - Set up rootfs (overlay mounts)
       - pivot_root
       - Set hostname
       - Configure network (via CNI plugin)
       - Drop capabilities
       - Set seccomp filters
       - Set AppArmor/SELinux labels
       - execve(container entrypoint)
5.  Container process is now running, fully isolated
```

Steps 4a-4b are exactly what the scripts in `demos/` do, just in C/Go instead of bash.

---

## References

- `man 7 namespaces` - the definitive reference
- `man 7 user_namespaces` - UID mapping details
- `man 2 unshare`, `man 2 clone`, `man 2 setns` - the syscalls
- `man 7 cgroups` - resource limits (the other half of containers)
- `man 8 nsenter`, `man 1 unshare` - the CLI tools
- `man 8 ip-netns` - network namespace management
- [LWN namespaces series](https://lwn.net/Articles/531114/) - Michael Kerrisk's deep dive
- OCI runtime spec - what container runtimes actually implement
