# Kubernetes Cluster Setup & Deployment Guide

This guide outlines the step-by-step commands used to bootstrap a Kubernetes cluster using `kubeadm`, configure `containerd` as the container runtime, install the Calico CNI network plugin, and deploy a sample NGINX application.

---

## Phase 1: System Preparation & Dependencies

Before installing Kubernetes components, the underlying Linux host must be updated, swap must be disabled, and specific kernel modules and networking parameters must be configured.

### 1. Update System & Install Prerequisites
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl gpg ca-certificates apt-transport-https
```
* **Explanation:** Updates the local package index, upgrades existing packages to their latest versions, and installs essential utilities (`curl`, `gpg`, `ca-certificates`, `apt-transport-https`) required to securely download and verify external package repositories.

### 2. Disable Swap
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```
* **Explanation:** Kubernetes requires swap memory to be disabled so the `kubelet` can accurately manage and allocate memory resources to containers. `swapoff -a` disables swap immediately, while the `sed` command comments out swap entries in `/etc/fstab` so it remains disabled across reboots.

### 3. Configure Kernel Modules
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```
* **Explanation:** Ensures the `overlay` (used by container filesystems) and `br_netfilter` (allows `iptables` to see bridged traffic) kernel modules load automatically at boot via `/etc/modules-load.d/k8s.conf`, and loads them immediately into the active kernel using `modprobe`. *(Note: Command 5 and 6 in your history were duplicates; only one execution is needed).*

### 4. Configure Sysctl Networking Parameters
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```
* **Explanation:** Enables IP forwarding and ensures bridged IPv4 and IPv6 traffic passes through `iptables` for proper pod-to-pod and service networking. `sysctl --system` applies these configuration changes immediately without requiring a reboot.

---

## Phase 2: Container Runtime Setup (`containerd`)

Kubernetes requires a Container Runtime Interface (CRI) to pull images and run containers.

### 5. Install & Configure `containerd`
```bash
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```
* **Explanation:** Installs `containerd`, generates its default configuration file at `/etc/containerd/config.toml`, and updates `SystemdCgroup` to `true`. Using the `systemd` cgroup driver ensures consistency between `containerd` and `kubelet`, preventing resource management conflicts.

### 6. Start & Enable `containerd`
```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd
```
* **Explanation:** Restarts `containerd` to apply the updated `systemd` cgroup configuration, enables it to start automatically on boot, and verifies that the service is active and running.

---

## Phase 3: Install Kubernetes Components (`kubeadm`, `kubelet`, `kubectl`)

### 7. Add the Official Kubernetes Repository
```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
```
* **Explanation:** Creates a secure keyring directory, downloads and imports the GPG signing key for Kubernetes `v1.37`, adds the official Kubernetes APT repository to the system's sources list, and refreshes the package index.

### 8. Install & Pin Kubernetes Binaries
```bash
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
```
* **Explanation:** 
  * `kubelet`: The node agent that runs on all machines and manages pods/containers.
  * `kubeadm`: The tool used to bootstrap and initialize the cluster.
  * `kubectl`: The command-line interface for interacting with the cluster.
  * `apt-mark hold` prevents these packages from being accidentally upgraded during routine `apt upgrade` runs, which could break cluster version compatibility.
  * `systemctl enable --now kubelet` enables and starts the `kubelet` service (it will wait in a crash-loop until `kubeadm init` provides its configuration).

### 9. Verify Installations
```bash
kubeadm version
kubelet --version
kubectl version --client
```
* **Explanation:** Confirms that all three Kubernetes binaries are installed properly and outputs their version details.

---

## Phase 4: Initialize Control Plane & Networking

### 10. Check Node IP & Initialize the Cluster
```bash
hostname -I
sudo kubeadm init \
  --apiserver-advertise-address=10.97.0.20 \
  --pod-network-cidr=192.168.0.0/16
```
* **Explanation:** `hostname -I` retrieves the host's IP address (`10.97.0.20`). `kubeadm init` bootstraps the Kubernetes control plane components (API Server, Scheduler, Controller Manager, etcd), advertising the API server on `10.97.0.20` and allocating `192.168.0.0/16` as the virtual IP address range for pods (the default CIDR expected by Calico).

> **Note:** After running `kubeadm init`, you typically configure `kubectl` access for your non-root user (`mkdir -p $HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config && sudo chown $(id -u):$(id -g) $HOME/.kube/config`) before running `kubectl` commands.

### 11. Inspect Initial Cluster State
```bash
kubectl get nodes
kubectl get namespace
```
* **Explanation:** Lists the nodes in the cluster (the control plane node will initially show a `NotReady` status until a network plugin is installed) and displays the default namespaces (`default`, `kube-system`, `kube-public`, `kube-node-lease`).

### 12. Install Calico CNI (Container Network Interface)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
```
* **Explanation:** Deploys Calico (`v3.33.0`) into the cluster. A CNI plugin is mandatory for pods to communicate with each other across nodes and for CoreDNS to start functioning.

### 13. Verify Cluster Readiness & Generate Worker Join Command
```bash
kubectl get pods -n kube-system
kubectl get namespace
kubectl get nodes
sudo kubeadm token create --print-join-command
kubectl get nodes -o wide
```
* **Explanation:**
  * `kubectl get pods -n kube-system`: Monitors system pods (like `calico-node` and `coredns`) until they reach the `Running` state.
  * `kubectl get nodes`: Confirms the node status has transitioned from `NotReady` to `Ready`.
  * `kubeadm token create --print-join-command`: Generates a fresh bootstrap token and outputs the exact `kubeadm join ...` command needed to attach worker nodes to this control plane.
  * `kubectl get nodes -o wide`: Displays extended node information, including internal IPs, OS images, kernel versions, and container runtime versions.

---

## Phase 5: Test Cluster with a Sample Application

### 14. Deploy & Expose NGINX
```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl get pods -o wide
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
```
* **Explanation:**
  * `kubectl create deployment...`: Creates a Deployment named `nginx` running 2 identical replicas (pods) of the official `nginx` container image.
  * `kubectl get pods -o wide`: Verifies that both NGINX pods are scheduled, running, and shows which nodes and internal pod IPs they received.
  * `kubectl expose deployment...`: Creates a Kubernetes `Service` of type `NodePort`, which opens a static port (in the `30000–32767` range) on every node's IP address and forwards external traffic on that port to port `80` of the NGINX pods.
  * `kubectl get svc nginx`: Displays the service details, including its `ClusterIP` and the assigned external `NodePort` (e.g., `80:3xxxx/TCP`) that you can use to access NGINX in a browser via `http://<Node-IP>:<NodePort>`.





# Summary
```bash
    1  sudo apt update && sudo apt upgrade -y
    2  sudo apt install -y curl gpg ca-certificates apt-transport-https
    3  sudo swapoff -a
    4  sudo sed -i '/ swap / s/^/#/' /etc/fstab
    5  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF




    6  cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    7  sudo modprobe overlay
    8  sudo modprobe br_netfilter
    9  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

   10  sudo sysctl --system
   11  sudo apt install -y containerd
   12  sudo mkdir -p /etc/containerd
   13  containerd config default | sudo tee /etc/containerd/config.toml
   14  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
   15  sudo systemctl restart containerd
   16  sudo systemctl enable containerd
   17  sudo systemctl status containerd
   18  sudo mkdir -p -m 755 /etc/apt/keyrings
   19  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   20  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
   21  sudo apt update
   22  sudo apt install -y kubelet kubeadm kubectl
   23  sudo apt-mark hold kubelet kubeadm kubectl
   24  sudo systemctl enable --now kubelet
   25  kubeadm version
   26  kubelet --version
   27  kubectl version --client
   28  hostname -I
   29  sudo kubeadm init   --apiserver-advertise-address=10.97.0.20   --pod-network-cidr=192.168.0.0/16
   30  kubectl get nodes
   31  kubectl get namespace
   32  kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml
   33  kubectl get pods -n kube-system
   34  kubectl get namespace
   35  kubectl get nodes
   36  sudo kubeadm token create --print-join-command
   37  kubectl get nodes -o wide
   38  kubectl create deployment nginx --image=nginx --replicas=2
   39  kubectl get pods -o wide
   40  kubectl expose deployment nginx --port=80 --type=NodePort
   41  kubectl get svc nginx
```