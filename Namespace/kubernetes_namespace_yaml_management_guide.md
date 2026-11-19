# Kubernetes Namespace YAML & Management Guide

A **Namespace** in Kubernetes is a virtual cluster inside a physical Kubernetes cluster. Namespaces allow you to divide cluster resources among multiple teams, projects, or environments (such as `dev`, `staging`, and `prod`), providing scope for resource names, access control (RBAC), and resource quotas.

## Built-in Default Namespaces

When you ran `kubectl get namespace` after initializing your `kubeadm` cluster, Kubernetes automatically created four system namespaces:

1. **`default`**: The default namespace for any object created without specifying a `namespace` field in its YAML or `kubectl` command.
2. **`kube-system`**: Reserved for core Kubernetes control-plane and system components (such as `kube-apiserver`, `etcd`, `coredns`, `kube-proxy`, and your `calico-node` pods). Avoid deploying user applications here.
3. **`kube-public`**: A publicly readable namespace (even by unauthenticated users) typically used to expose cluster-wide public information, such as cluster bootstrap details (`cluster-info` ConfigMap).
4. **`kube-node-lease`**: Holds `Lease` objects associated with each node, allowing the `kubelet` to send lightweight heartbeats so the control plane can detect node health and failures quickly.

## Complete `namespace.yaml` Example

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dev-team
  labels:
    environment: development
    team: backend
```

## Statement-by-Statement Explanation

### 1. Top-Level Fields

* **`apiVersion: v1`**
  * **What it does:** Specifies that `Namespace` belongs to the core Kubernetes `v1` API group.
* **`kind: Namespace`**
  * **What it does:** Declares that this manifest creates a **Namespace** object.
  * **Why it matters:** Unlike Pods, Deployments, or Services, a `Namespace` itself is a **cluster-scoped** resource—it cannot live inside another namespace.

### 2. `metadata` Section

* **`metadata:`**
  * **What it does:** Defines identifying information for the Namespace.
* **`name: dev-team`**
  * **What it does:** Sets the unique name of the Namespace across the entire cluster.
  * **Naming Rules:** Must be a valid DNS label (lowercase alphanumeric characters or `-`, starting and ending with an alphanumeric character, up to 63 characters).
  * **Scope Isolation:** Within `dev-team`, you can create a Deployment named `nginx-deployment` even if another `nginx-deployment` already exists in `default` or `prod`.
* **`labels:`**
  * **What it does:** Attaches metadata tags (`environment: development`, `team: backend`) to the Namespace.
  * **Why it matters:** Used by **NetworkPolicies** (e.g., allowing traffic only from Pods in namespaces labeled `environment: development`) and resource governance tools.

## Deploying Resources into a Specific Namespace

There are two ways to place resources (Pods, Deployments, Services) into a custom namespace:

### Method 1: Declaratively in the YAML Manifest (`metadata.namespace`)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  namespace: dev-team
  labels:
    app: nginx
spec:
  containers:
    - name: nginx-container
      image: nginx:1.27
```

### Method 2: Imperatively via `kubectl` Flag (`-n` / `--namespace`)

```bash
kubectl apply -f deployment.yaml -n dev-team
kubectl create deployment nginx --image=nginx -n dev-team
```

## Cross-Namespace Communication (DNS)

Namespaces isolate resource *names*, **not** network traffic by default. A Pod in `dev-team` can still communicate with a Service in `prod` (unless restricted by a `NetworkPolicy`) using its Full Qualified Domain Name (FQDN):

```text
<service-name>.<namespace-name>.svc.cluster.local
```

* **Same Namespace:** `http://nginx-service`
* **Across Namespaces:** `http://nginx-service.dev-team.svc.cluster.local`

## Namespaced vs. Cluster-Scoped Resources

Not every Kubernetes object lives inside a namespace:

| Namespaced Resources (`-n <namespace>`) | Cluster-Scoped Resources (Global) |
| :--- | :--- |
| `Pod` | `Node` |
| `ReplicaSet` | `Namespace` |
| `Deployment` | `PersistentVolume` (`PV`) |
| `Service` | `ClusterRole` / `ClusterRoleBinding` |
| `ConfigMap` & `Secret` | `StorageClass` |
| `PersistentVolumeClaim` (`PVC`) | `CustomResourceDefinition` (`CRD`) |

*(Tip: Run `kubectl api-resources --namespaced=true` or `--namespaced=false` to see the complete list on your cluster).*

## Essential Namespace Commands

```bash
# List all namespaces in the cluster
kubectl get namespaces   # or: kubectl get ns

# Create a namespace imperatively in one line
kubectl create namespace dev-team

# Create a namespace using YAML
kubectl apply -f namespace.yaml

# List Pods inside a specific namespace
kubectl get pods -n dev-team

# List Pods across ALL namespaces simultaneously
kubectl get pods -A   # or: --all-namespaces

# Switch your current kubectl context to use 'dev-team' by default
kubectl config set-context --current --namespace=dev-team

# Verify your active default namespace
kubectl config view --minify | grep namespace:

# Switch back to the 'default' namespace
kubectl config set-context --current --namespace=default

# Delete a namespace (WARNING: deletes ALL resources inside it!)
kubectl delete namespace dev-team
```