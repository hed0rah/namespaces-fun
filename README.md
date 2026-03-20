# namespaces-fun

Scripts and tools for working with Linux namespaces - the kernel primitives behind containers.

## What's Here

```
demos/
├── 01-uts-hostname.sh      UTS namespace - hostname isolation
├── 02-pid-namespace.sh      PID namespace - invisible processes
├── 03-net-namespace.sh      Network namespace - veth pairs, the Docker way
├── 04-mount-namespace.sh    Mount namespace - filesystem illusions
├── 05-user-namespace.sh     User namespace - fake root (no sudo!)
├── 06-ipc-namespace.sh      IPC namespace - isolated message queues
├── 07-mini-container.sh     Build a real container from scratch in bash
├── 08-namespace-snoop.sh    Inspect & enter existing namespaces
└── 09-cgroup-namespace.sh   Cgroup namespace - hidden resource limits

nsm/
├── nsm                      Namespace manager CLI tool
└── nsm-completions.bash     Bash tab completions

cheatsheet.md                Quick reference for namespace commands
deep-dive.md                 Namespaces from zero to container
```

## Usage

```bash
chmod +x demos/*.sh nsm/nsm

# Most scripts need root
sudo ./demos/01-uts-hostname.sh
sudo ./demos/02-pid-namespace.sh
sudo ./demos/03-net-namespace.sh

# 05 runs unprivileged - that's the point
./demos/05-user-namespace.sh

# Build a container from scratch with just unshare + pivot_root
sudo ./demos/07-mini-container.sh
```

## nsm - Namespace Manager

```bash
sudo cp nsm/nsm /usr/local/bin/nsm
source nsm/nsm-completions.bash

nsm list                          # List all namespaces
nsm create mybox --type net       # Create a named network namespace
nsm enter mybox                   # Enter it
nsm exec mybox -- ip addr show    # Run a command inside
nsm diff 1 $$                     # Compare your namespaces to init
nsm tree                          # Visualize namespace types
nsm inspect <pid>                 # Inspect a process's namespaces
nsm ps                            # Processes grouped by namespace
nsm monitor                       # Watch namespace events live
nsm destroy mybox                 # Clean up
```

## Requirements

- Linux kernel 4.6+ (for all namespace types)
- `util-linux` (`unshare`, `nsenter`, `lsns`)
- `iproute2` (`ip`)
- Root for most scripts (except 05)
- `debootstrap` for 07 (or any method to get a rootfs)
