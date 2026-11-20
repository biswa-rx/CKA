# Multipass – Complete Command Reference

> A practical guide to managing Ubuntu virtual machines using Multipass on Windows, Linux, and macOS.

## Table of Contents

1. [Introduction](#1-introduction)
2. [Basic CLI Commands](#2-basic-cli-commands)
3. [Installation and Version](#3-installation-and-version)
4. [Images](#4-images)
5. [Creating Virtual Machines](#5-creating-virtual-machines)
6. [Listing and Inspecting VMs](#6-listing-and-inspecting-vms)
7. [Connecting to VMs](#7-connecting-to-vms)
8. [VM Lifecycle Management](#8-vm-lifecycle-management)
9. [Resource Management](#9-resource-management)
10. [File Transfer and Mounting](#10-file-transfer-and-mounting)
11. [Snapshots](#11-snapshots)
12. [Clone and Recovery](#12-clone-and-recovery)
13. [Networking](#13-networking)
14. [Configuration and Settings](#14-configuration-and-settings)
15. [Aliases](#15-aliases)
16. [Availability Zones](#16-availability-zones)
17. [Deleting and Cleaning Up](#17-deleting-and-cleaning-up)
18. [Troubleshooting](#18-troubleshooting)
19. [Useful PowerShell Commands](#19-useful-powershell-commands)
20. [Complete Command Cheat Sheet](#20-complete-command-cheat-sheet)

---

# 1. Introduction

Multipass is a tool developed by Canonical for creating and managing lightweight Ubuntu virtual machines.

You can use it to create multiple Ubuntu environments without manually installing Ubuntu using ISO files.

### Important terminology

| Term | Meaning |
|---|---|
| Host | Your physical Windows/Linux/macOS machine |
| Instance | A virtual machine created by Multipass |
| Image | The Ubuntu operating system template |
| Primary | The default Multipass instance |
| Snapshot | A saved state of a VM |
| Mount | Sharing a host directory with a VM |
| Driver | Backend used to run virtual machines |

### Basic architecture

```text
Physical Machine (Windows)
        |
        +---- Multipass CLI
        |
        +---- Multipass Service
                  |
                  +---- Ubuntu VM 1
                  |       |
                  |       +---- Docker
                  |       +---- Kubernetes
                  |
                  +---- Ubuntu VM 2
                  |       |
                  |       +---- Kubernetes Node
                  |
                  +---- Ubuntu VM 3
                          |
                          +---- Kubernetes Node
```

---

# 2. Basic CLI Commands

### Display all available commands

```powershell
multipass
```

```powershell
multipass help
```

### Get help for a specific command

```powershell
multipass help launch
multipass help list
multipass help delete
multipass help start
multipass help stop
```

### Increase logging verbosity

```powershell
multipass -v list
multipass -vv list
multipass -vvv list
multipass -vvvv list
```

Useful when troubleshooting Multipass.

---

# 3. Installation and Version

### Check Multipass version

```powershell
multipass version
```

### Check installation path

```powershell
where.exe multipass
```

### Check available CLI commands

```powershell
multipass help
```

---

# 4. Images

Images are operating system templates used to create virtual machines.

### List available images

```powershell
multipass find
```

### List remote images

```powershell
multipass find --all
```

### Search for Ubuntu LTS

```powershell
multipass find lts
```

### Launch a specific Ubuntu version

```powershell
multipass launch 24.04
```

```powershell
multipass launch 22.04
```

```powershell
multipass launch 26.04
```

*Note: Image availability depends on the configured Multipass remotes.*

---

# 5. Creating Virtual Machines

### Create a VM with default configuration

```powershell
multipass launch
```

### Create a VM with a custom name

```powershell
multipass launch --name ubuntu-vm
```

### Create Ubuntu 24.04

```powershell
multipass launch 24.04 --name ubuntu-vm
```

### Specify CPU, RAM and Disk

```powershell
multipass launch 24.04 --name ubuntu-vm --cpus 2 --memory 2G --disk 8G
```

### Create a lightweight VM

```powershell
multipass launch 24.04 --name test-vm --cpus 1 --memory 1G --disk 8G
```

### Create a VM with more resources

```powershell
multipass launch 24.04 --name master --cpus 2 --memory 4G --disk 20G
```

### Create a VM with cloud-init

```powershell
multipass launch 24.04 --name ubuntu-vm --cloud-init cloud-init.yaml
```

### Create a VM with a custom network

```powershell
multipass launch 24.04 --name ubuntu-vm --network <network-name>
```

### Create a VM with bridged networking

```powershell
multipass launch 24.04 --name ubuntu-vm --bridged
```

### Create a VM with a mounted directory

```powershell
multipass launch 24.04 --name ubuntu-vm --mount "C:\Users\User\Projects:/projects"
```

### Specify VM startup timeout

```powershell
multipass launch 24.04 --name ubuntu-vm --timeout 600
```

---

# 6. Listing and Inspecting VMs

### List all VMs

```powershell
multipass list
```

### Display detailed information

```powershell
multipass info ubuntu-vm
```

### Display information about all VMs

```powershell
multipass info
```

### Display snapshot information

```powershell
multipass info --snapshots ubuntu-vm
```

### Display VM information in JSON

```powershell
multipass list --format json
```

### Display VM information in YAML

```powershell
multipass list --format yaml
```

### Display VM information in CSV

```powershell
multipass list --format csv
```

### List snapshots

```powershell
multipass list --snapshots
```

---

# 7. Connecting to VMs

### Open an interactive shell

```powershell
multipass shell ubuntu-vm
```

### Execute a single Linux command

```powershell
multipass exec ubuntu-vm -- ls -la
```

### Check Ubuntu version

```powershell
multipass exec ubuntu-vm -- lsb_release -a
```

### Check available memory

```powershell
multipass exec ubuntu-vm -- free -h
```

### Check disk usage

```powershell
multipass exec ubuntu-vm -- df -h
```

### Check IP address

```powershell
multipass exec ubuntu-vm -- hostname -I
```

### Update Ubuntu packages

```powershell
multipass exec ubuntu-vm -- sudo apt update
```

### Install Docker

```powershell
multipass exec ubuntu-vm -- sudo apt install docker.io -y
```

### Execute multiple commands

```powershell
multipass exec ubuntu-vm -- bash -c "sudo apt update && sudo apt upgrade -y"
```

---

# 8. VM Lifecycle Management

Multipass provides several commands to control VM states.

### Start a VM

```powershell
multipass start ubuntu-vm
```

### Start all VMs

```powershell
multipass start --all
```

### Stop a VM

```powershell
multipass stop ubuntu-vm
```

### Stop all VMs

```powershell
multipass stop --all
```

### Restart a VM

```powershell
multipass restart ubuntu-vm
```

### Restart all VMs

```powershell
multipass restart --all
```

### Suspend a VM

```powershell
multipass suspend ubuntu-vm
```

### Suspend all VMs

```powershell
multipass suspend --all
```

### Wait until Multipass is ready

```powershell
multipass wait-ready
```

### Important differences

| Command | Behaviour |
|---|---|
| start | Starts a stopped or suspended VM |
| stop | Shuts down the VM |
| restart | Restarts the VM |
| suspend | Saves VM state and pauses execution |

**Resource usage:**

- Stopped VMs do not consume active VM CPU/RAM resources.
- Suspended VMs preserve their execution state and memory.
- Running VMs consume CPU, RAM and other allocated resources.

---

# 9. Resource Management

### Specify resources during VM creation

```powershell
multipass launch 24.04 --name ubuntu-vm --cpus 2 --memory 2G --disk 8G
```

### View allocated resources

```powershell
multipass info ubuntu-vm
```

### Change CPU allocation

```powershell
multipass set local.ubuntu-vm.cpus=2
```

### Change memory allocation

```powershell
multipass set local.ubuntu-vm.memory=2G
```

### Change disk allocation

```powershell
multipass set local.ubuntu-vm.disk=8G
```

**Important:** Disk allocation is generally not a simple disk shrink operation. Do not assume that changing the configured disk value will safely reduce an existing VM's virtual disk. For a smaller VM, create a new instance with a smaller `--disk` value and migrate your data.

---

# 10. File Transfer and Mounting

## Mount

Mounting shares a directory between the host and guest.

### Mount a Windows directory

```powershell
multipass mount "C:\Users\User\Projects" ubuntu-vm:/projects
```

### Mount a Linux directory inside the VM

```powershell
multipass exec ubuntu-vm -- ls /projects
```

### Unmount a directory

```powershell
multipass umount ubuntu-vm:/projects
```

## Transfer

Transfer copies files without maintaining a shared mount.

### Copy Windows file to Ubuntu

```powershell
multipass transfer "C:\Users\User\Desktop\file.txt" ubuntu-vm:/home/ubuntu/
```

### Copy Ubuntu file to Windows

```powershell
multipass transfer ubuntu-vm:/home/ubuntu/file.txt "C:\Users\User\Desktop\"
```

### Copy a directory

```powershell
multipass transfer --recursive "C:\Users\User\Projects" ubuntu-vm:/home/ubuntu/
```

### Copy a file between two VMs

```powershell
multipass transfer vm1:/home/ubuntu/file.txt vm2:/home/ubuntu/
```

---

# 11. Snapshots

Snapshots capture the state of a VM at a particular point in time.

They are useful before making major configuration changes.

### Create a snapshot

```powershell
multipass snapshot ubuntu-vm
```

### Create a named snapshot

```powershell
multipass snapshot ubuntu-vm --name before-kubernetes
```

### Create a snapshot with a comment

```powershell
multipass snapshot ubuntu-vm --name before-update --comment "Before Ubuntu package update"
```

### List snapshots

```powershell
multipass list --snapshots
```

### View snapshot information

```powershell
multipass info ubuntu-vm --snapshots
```

### Restore a snapshot

```powershell
multipass restore ubuntu-vm.before-kubernetes
```

### Restore a snapshot without confirmation

```powershell
multipass restore ubuntu-vm.before-kubernetes --destructive
```

**Important:** Snapshot creation and restoration require the VM to be stopped. Restoring can discard changes made after the snapshot, so understand the restore options before proceeding.

---

# 12. Clone and Recovery

## Clone

Create another VM based on an existing instance.

```powershell
multipass clone ubuntu-vm
```

### Clone with a custom name

```powershell
multipass clone ubuntu-vm --name ubuntu-vm-copy
```

### Clone a specific snapshot

```powershell
multipass clone ubuntu-vm.before-kubernetes --name ubuntu-backup
```

## Recovery

### Delete an instance without immediately purging it

```powershell
multipass delete ubuntu-vm
```

### Recover a deleted instance

```powershell
multipass recover ubuntu-vm
```

### List instances

```powershell
multipass list
```

---

# 13. Networking

### List available network interfaces

```powershell
multipass networks
```

### Display VM IP address

```powershell
multipass info ubuntu-vm
```

### Display network information inside Ubuntu

```powershell
multipass exec ubuntu-vm -- ip addr
```

### Display routing table

```powershell
multipass exec ubuntu-vm -- ip route
```

### Display DNS configuration

```powershell
multipass exec ubuntu-vm -- resolvectl status
```

### Test internet connectivity

```powershell
multipass exec ubuntu-vm -- ping -c 4 google.com
```

### Launch using bridged networking

```powershell
multipass launch 24.04 --name ubuntu-vm --bridged
```

### Launch using a particular network interface

```powershell
multipass launch 24.04 --name ubuntu-vm --network <network-name>
```

---

# 14. Configuration and Settings

Multipass provides configuration settings through `get` and `set`.

### Get a setting

```powershell
multipass get local.driver
```

### Get all available settings

```powershell
multipass get --keys
```

### Set a configuration value

```powershell
multipass set local.driver=hyperv
```

### Configure the default primary instance name

```powershell
multipass set client.primary-name=ubuntu-vm
```

### Configure the default bridged network interface

```powershell
multipass set local.bridged-interface=<interface-name>
```

### Configure instance CPU

```powershell
multipass set local.ubuntu-vm.cpus=2
```

### Configure instance memory

```powershell
multipass set local.ubuntu-vm.memory=2G
```

### Configure instance disk

```powershell
multipass set local.ubuntu-vm.disk=8G
```

**Note:** Available setting keys and supported values depend on your Multipass version and platform. Check `multipass get --keys` before changing settings.

---

# 15. Aliases

Aliases allow you to execute commands inside an instance directly from the host.

### Create an alias

```powershell
multipass alias ubuntu-vm:ls
```

### List aliases

```powershell
multipass aliases
```

### Remove an alias

```powershell
multipass unalias ls
```

### Select preferred alias context

```powershell
multipass prefer ubuntu-vm
```

Aliases are useful when repeatedly executing commands inside a particular VM.

---

# 16. Availability Zones

Multipass supports availability zones to group virtual machine instances.

### List zones

```powershell
multipass zones
```

### Enable a zone

```powershell
multipass enable-zones <zone-name>
```

### Disable a zone

```powershell
multipass disable-zones <zone-name>
```

### Launch an instance in a specific zone

```powershell
multipass launch 24.04 --name ubuntu-vm --zone <zone-name>
```

---

# 17. Deleting and Cleaning Up

There is an important difference between `delete` and `purge`.

### Delete one VM

```powershell
multipass delete ubuntu-vm
```

### Delete all VMs

```powershell
multipass delete --all
```

### Permanently remove deleted VMs

```powershell
multipass purge
```

### Delete and permanently purge all VMs

```powershell
multipass delete --all
multipass purge
```

### Check remaining VMs

```powershell
multipass list
```

**Warning:** `delete` marks instances for deletion, while `purge` permanently removes deleted instances and their associated data. Once purged, they cannot be recovered through Multipass.

---

# 18. Troubleshooting

### Check Multipass version

```powershell
multipass version
```

### Check VM status

```powershell
multipass list
```

### Inspect VM details

```powershell
multipass info ubuntu-vm
```

### Check Multipass service on Windows

```powershell
Get-Service Multipass
```

### Restart Multipass service

Run PowerShell as Administrator:

```powershell
Restart-Service Multipass
```

### Check service status

```powershell
Get-Service Multipass
```

### Check Hyper-V services

```powershell
Get-Service vmms
```

### Check Hyper-V feature

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All
```

### Check cloud-init status inside Ubuntu

```powershell
multipass exec ubuntu-vm -- cloud-init status
```

### View cloud-init logs

```powershell
multipass exec ubuntu-vm -- sudo cat /var/log/cloud-init.log
```

### Check disk usage inside Ubuntu

```powershell
multipass exec ubuntu-vm -- df -h
```

### Check memory usage

```powershell
multipass exec ubuntu-vm -- free -h
```

---

# 19. Useful PowerShell Commands

These commands are useful when managing Multipass on Windows.

### Find Multipass executable

```powershell
where.exe multipass
```

### Check Multipass process

```powershell
Get-Process multipass*
```

### Check Multipass service

```powershell
Get-Service *multipass*
```

### List all VMs

```powershell
multipass list
```

### Display VM disk usage

```powershell
multipass info ubuntu-vm
```

### Display host disk space

```powershell
Get-Volume
```

### Display host RAM

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory
```

### Display CPU information

```powershell
Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors
```

### Display network configuration

```powershell
Get-NetIPConfiguration
```

---

# 20. Complete Command Cheat Sheet

| Command | Purpose |
|---|---|
| `multipass help` | Display CLI help |
| `multipass help <command>` | Help for a specific command |
| `multipass version` | Show version |
| `multipass find` | Find available images |
| `multipass find --all` | Find all available images |
| `multipass launch` | Create a VM |
| `multipass clone` | Clone an existing VM |
| `multipass list` | List VMs |
| `multipass info` | Display VM information |
| `multipass shell` | Open interactive shell |
| `multipass exec` | Execute a command inside VM |
| `multipass start` | Start VM |
| `multipass stop` | Stop VM |
| `multipass restart` | Restart VM |
| `multipass suspend` | Suspend VM |
| `multipass delete` | Mark VM for deletion |
| `multipass recover` | Recover deleted VM |
| `multipass purge` | Permanently remove deleted VMs |
| `multipass snapshot` | Create snapshot |
| `multipass restore` | Restore snapshot |
| `multipass list --snapshots` | List snapshots |
| `multipass mount` | Mount host directory |
| `multipass umount` | Unmount directory |
| `multipass transfer` | Transfer files |
| `multipass networks` | List network interfaces |
| `multipass get` | Read configuration |
| `multipass set` | Change configuration |
| `multipass alias` | Create command alias |
| `multipass aliases` | List aliases |
| `multipass unalias` | Remove alias |
| `multipass prefer` | Select alias context |
| `multipass zones` | List availability zones |
| `multipass enable-zones` | Enable availability zone |
| `multipass disable-zones` | Disable availability zone |
| `multipass wait-ready` | Wait for service readiness |

---

# 21. Recommended Daily Workflow

For everyday Ubuntu VM management, these are the commands you will use most frequently.

### Step 1: Create a VM

```powershell
multipass launch 24.04 --name kube-control --cpus 2 --memory 2G --disk 8G
```

### Step 2: Check VM

```powershell
multipass list
```

### Step 3: Connect

```powershell
multipass shell kube-control
```

### Step 4: Install required packages

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 5: Work with Kubernetes

Install Docker, containerd, kubectl, kubeadm, or other required tools.

### Step 6: Exit VM

```bash
exit
```

### Step 7: Stop VM when not needed

```powershell
multipass stop kube-control
```

### Step 8: Start VM when needed again

```powershell
multipass start kube-control
```

---

## Official Documentation

- [Multipass Official Documentation](https://canonical.com/multipass/docs/latest/)
- [Command-Line Interface Reference](https://canonical.com/multipass/docs/latest/reference/command-line-interface/)
- [Multipass GitHub Repository](https://github.com/canonical/multipass)

> **Important:** This document covers the major Multipass CLI commands and common options. The exact options can vary between releases. Use `multipass help <command>` to see the authoritative syntax for your installed version.

