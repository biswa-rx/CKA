# Kubernetes Static Pods Guide

A **Static Pod** is a Pod managed **directly by the `kubelet`** daemon on a specific node—without going through the Kubernetes API server (`kube-apiserver`), scheduler (`kube-scheduler`), or any controller (`Deployment`, `ReplicaSet`, or `DaemonSet`).

* The `kubelet` continuously watches a designated local directory on the host machine (default: `/etc/kubernetes/manifests`).
* Whenever a YAML or JSON Pod manifest is placed in that directory, the `kubelet` automatically creates the Pod.
* If a Static Pod crashes or is deleted via `kubectl`, the `kubelet` **immediately recreates it** as long as the manifest file remains in the directory.

> **Key Difference from Regular Pods:** Regular Pods are stored in `etcd` via the API server and scheduled onto nodes. Static Pods are defined by local files on the node itself—the `kubelet` creates a "mirror Pod" object in the API server so you can view them with `kubectl get pods`, even though no controller owns them.

## Why Static Pods Exist (Control Plane Bootstrap)

Static Pods are how `kubeadm` bootstraps core control-plane components on a node before the cluster is fully up:

* `kube-apiserver`
* `kube-controller-manager`
* `kube-scheduler`
* `etcd`

Because the API server and scheduler are themselves running as Static Pods on the control-plane node, the `kubelet` can start them directly from local manifests on disk without needing a functioning API server first.

## How to Configure the Static Pod Directory

The path watched by `kubelet` is configured via the **`staticPodPath`** setting in the KubeletConfiguration file (or the `--pod-manifest-path` flag in older setups).

### 1. Check Where `staticPodPath` Is Configured

On a `kubeadm`-initialized node, `kubelet` reads its configuration from `/var/lib/kubelet/config.yaml`:

```bash
grep -i staticPodPath /var/lib/kubelet/config.yaml
```

Typical output:

```yaml
staticPodPath: /etc/kubernetes/manifests
```

### 2. Inspect Existing Control-Plane Static Pods

```bash
# List manifest files on the control-plane node
ls -la /etc/kubernetes/manifests

# View the mirror Pods in the API server (notice the '-<node-name>' suffix)
kubectl get pods -n kube-system
```

## Complete Static Pod Manifest Example (`/etc/kubernetes/manifests/static-nginx.yaml`)

A Static Pod manifest is a standard `Pod` YAML file (it **cannot** be a `Deployment`, `ReplicaSet`, or `Service`).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
  labels:
    role: static-web
spec:
  containers:
    - name: nginx-container
      image: nginx:1.27
      ports:
        - containerPort: 80
```

## Statement-by-Statement Breakdown

* **`apiVersion: v1`**
  * Uses the core `v1` API group for a standalone `Pod` definition.
* **`kind: Pod`**
  * Must be `Pod`. The `kubelet` reads Pod specifications directly from local files and does not process higher-level controllers like `Deployment` or `DaemonSet`.
* **`metadata.name: static-nginx`**
  * Sets the base Pod name. When `kubelet` registers the corresponding **mirror Pod** with the API server, Kubernetes appends `-<node-name>` to the name (for example, `static-nginx-controlplane`).
* **`metadata.labels:`**
  * Attaches labels (`role: static-web`) to the Pod and its mirror Pod.
* **`spec.containers:`**
  * Defines the container(s), image (`nginx:1.27`), and ports (`80`) to run on that specific node.

## Lifecycle & Important Behaviors

1. **Creating a Static Pod:** Drop a valid YAML/JSON file into `/etc/kubernetes/manifests/`. Within a few seconds, `kubelet` starts the container and creates a mirror Pod in the API server.
2. **Updating a Static Pod:** Edit the manifest file in `/etc/kubernetes/manifests/` and save. `kubelet` detects the file change and automatically restarts/recreates the Pod with the new spec.
3. **Deleting a Static Pod (`kubectl delete` vs. Removing the File):**
   * Running `kubectl delete pod static-nginx-<node-name>` **will not permanently delete** a Static Pod—`kubelet` will immediately recreate it because the file still exists in `/etc/kubernetes/manifests/`.
   * To permanently delete a Static Pod, **remove (or move out of the directory) its manifest file** from `/etc/kubernetes/manifests/`.
4. **No `ReplicaSet` or `Deployment` Controller:** Static Pods do not have an owning controller (`OwnerReferences` points to a `Node` rather than a `ReplicaSet`), and they cannot be scaled with `kubectl scale`.
5. **Namespace Behavior:** Static Pods belong to the `default` namespace (unless specified otherwise in `metadata.namespace`), and their mirror Pods are read-only from the API server perspective.

## Static Pods vs. DaemonSets

| Feature | Static Pods | DaemonSets |
| :--- | :--- | :--- |
| **Managed By** | Local `kubelet` daemon on each node | `DaemonSet` controller via API server |
| **Depends on API Server?** | No (works even if control plane is down) | Yes |
| **Pod Naming** | `<pod-name>-<node-name>` | `<daemonset-name>-<random-hash>` |
| **How to Delete** | Delete the YAML file from `staticPodPath` | `kubectl delete ds <name>` |
| **Primary Use Case** | Control-plane components (`etcd`, `kube-apiserver`) | Node-level agents (`calico-node`, `kube-proxy`, log collectors) |

## Hands-On Lab & Inspection Commands

```bash
# 1. Create a Static Pod by writing a manifest to /etc/kubernetes/manifests/
cat <<EOF | sudo tee /etc/kubernetes/manifests/static-nginx.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-nginx
  labels:
    app: static-nginx
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
EOF

# 2. Watch the Pod start up (it will be named static-nginx-<your-node-name>)
kubectl get pods -o wide -w

# 3. Test self-healing: delete the mirror Pod via kubectl and watch kubelet recreate it
kubectl delete pod static-nginx-$(hostname)
kubectl get pods -o wide

# 4. Permanently delete the Static Pod by removing its manifest file
sudo rm /etc/kubernetes/manifests/static-nginx.yaml
kubectl get pods -o wide
```