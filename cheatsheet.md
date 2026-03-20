# Linux Namespaces Cheatsheet

## The 8 Namespace Types

| Type | Flag | Clone Flag | Isolates | Since |
|------|------|------------|----------|-------|
| **Mount** | `CLONE_NEWNS` | `unshare -m` | Filesystem mount points | 2.4.19 (2002) |
| **UTS** | `CLONE_NEWUTS` | `unshare -u` | Hostname, NIS domain | 2.6.19 (2006) |
| **IPC** | `CLONE_NEWIPC` | `unshare -i` | SysV IPC, POSIX mqueues | 2.6.19 (2006) |
| **PID** | `CLONE_NEWPID` | `unshare -p` | Process IDs | 2.6.24 (2008) |
| **Network** | `CLONE_NEWNET` | `unshare -n` | Network stack (interfaces, routes, iptables) | 2.6.29 (2009) |
| **User** | `CLONE_NEWUSER` | `unshare -U` | UIDs, GIDs, capabilities | 3.8 (2013) |
| **Cgroup** | `CLONE_NEWCGROUP` | `unshare -C` | Cgroup root directory | 4.6 (2016) |
| **Time** | `CLONE_NEWTIME` | `unshare -T` | CLOCK_MONOTONIC, CLOCK_BOOTTIME | 5.6 (2020) |

## Key Commands

### unshare - Create new namespace(s) and run a program in them

```bash
# New UTS namespace, change hostname
sudo unshare --uts bash -c 'hostname mybox; bash'

# New PID namespace (must fork + remount /proc)
sudo unshare --pid --fork --mount-proc bash

# New network namespace (blank network stack)
sudo unshare --net bash

# All the namespaces (basically a container)
sudo unshare --pid --uts --mount --ipc --net --fork --mount-proc bash

# Rootless - user namespace (no sudo!)
unshare --user --map-root-user bash
```

### nsenter - Enter an existing namespace

```bash
# Enter all namespaces of PID 12345
sudo nsenter --target 12345 --all bash

# Enter just the network namespace
sudo nsenter --target 12345 --net bash

# Enter a Docker container's namespaces
sudo nsenter --target $(docker inspect -f '{{.State.Pid}}' mycontainer) --all bash
```

### ip netns - Manage named network namespaces

```bash
ip netns add myns                        # Create
ip netns list                            # List
ip netns exec myns bash                  # Enter
ip netns exec myns ip addr show          # Run command inside
ip netns del myns                        # Delete

# Create a veth pair and connect namespaces
ip link add veth0 type veth peer name veth1
ip link set veth1 netns myns
ip addr add 10.0.0.1/24 dev veth0
ip netns exec myns ip addr add 10.0.0.2/24 dev veth1
ip link set veth0 up
ip netns exec myns ip link set veth1 up
```

### Inspection

```bash
# See your own namespaces
ls -la /proc/$$/ns/

# Compare two processes' namespaces
readlink /proc/1/ns/pid       # init's PID namespace
readlink /proc/$$/ns/pid      # your PID namespace

# List all namespaces on the system
lsns

# List only network namespaces
lsns -t net

# Find all processes in a specific namespace
lsns -t pid -o NS,PID,COMMAND

# Check namespace of a Docker container
docker inspect -f '{{.State.Pid}}' <container>
ls -la /proc/<that_pid>/ns/
```

## /proc Namespace Files

```
/proc/<pid>/ns/
├── cgroup    → cgroup:[4026531835]
├── ipc       → ipc:[4026531839]
├── mnt       → mnt:[4026531841]
├── net       → net:[4026531840]
├── pid       → pid:[4026531836]
├── pid_for_children
├── time      → time:[4026531834]
├── time_for_children
├── user      → user:[4026531837]
└── uts       → uts:[4026531838]
```

The number in brackets is the **inode number**. Same inode = same namespace.

## Syscalls

| Syscall | Purpose |
|---------|---------|
| `clone(flags)` | Create child in new namespace(s) |
| `unshare(flags)` | Move calling process into new namespace(s) |
| `setns(fd, nstype)` | Join an existing namespace (what nsenter uses) |

## Quick Recipes

### Isolate a process's network
```bash
sudo unshare --net -- bash -c '
    # This process has NO network access
    curl google.com  # fails
'
```

### Run a process with a different hostname
```bash
sudo unshare --uts -- bash -c 'hostname devbox; exec my-app'
```

### Rootless "container"
```bash
unshare --user --map-root-user --pid --fork --mount-proc bash
# You're now "root" with isolated PIDs, no sudo needed
```

### Spy on what namespaces Docker uses
```bash
# Start a container
docker run -d --name test alpine sleep 3600
PID=$(docker inspect -f '{{.State.Pid}}' test)

# Compare its namespaces to init
for ns in /proc/$PID/ns/*; do
    type=$(basename $ns)
    container=$(readlink $ns)
    host=$(readlink /proc/1/ns/$type)
    [[ "$container" != "$host" ]] && echo "ISOLATED: $type"
done
```

### Limit PIDs in a namespace (cgroups v2)
```bash
mkdir /sys/fs/cgroup/mygroup
echo 50 > /sys/fs/cgroup/mygroup/pids.max
echo $$ > /sys/fs/cgroup/mygroup/cgroup.procs
```
