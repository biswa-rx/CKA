# Kubernetes Admission Controllers Guide

An **Admission Controller** is a piece of code compiled into the **`kube-apiserver`** binary that intercepts requests to the Kubernetes API server **after** the request is authenticated and authorized, **but before** the object is persisted into `etcd`.

Admission controllers allow cluster administrators to enforce security policies, set default resource configurations, inject sidecar containers, and prevent misconfigurations across the entire cluster.

## 1. Where Admission Controllers Fit in the API Request Lifecycle

Whenever you run `kubectl apply -f pod.yaml` (or any API write operation like `CREATE`, `UPDATE`, `DELETE`, or `CONNECT`), the request passes through a strict security and validation pipeline inside `kube-apiserver`:

```
kubectl apply
     │
     ▼
1. Authentication       (Who are you? Certificates, Tokens, OIDC)
     │
     ▼
2. Authorization        (Are you allowed to do this? RBAC, Node, Webhook)
     │
     ▼
3. Mutating Admission   (Can modify/patch the object — e.g., inject defaults/sidecars)
     │
     ▼
4. Object Schema Validation (Validates YAML fields against OpenAPI schema)
     │
     ▼
5. Validating Admission (Enforces policy rules — Pass or Reject; cannot modify)
     │
     ▼
6. Persist to etcd      (Object is saved to cluster state)
```

> **Note:** Read-only requests (`GET`, `LIST`, `WATCH`) bypass Admission Controllers completely.

## 2. The Two Phases of Admission Controllers

Admission controllers operate in two distinct phases:

### Phase 1: Mutating Admission Controllers
* **What they do:** Can **modify (mutate)** the incoming Kubernetes object before it is saved.
* **Execution Order:** Run **sequentially** (one after another), because one mutating controller's changes might affect the next.
* **Examples:**
  * `DefaultStorageClass`: Automatically adds the cluster's default `storageClassName` to a `PersistentVolumeClaim` if the user left it blank.
  * `LimitRanger`: Injects default CPU/memory `requests` and `limits` into containers that don't specify them.
  * `MutatingAdmissionWebhook`: Calls external custom webhooks (used by Istio/Linkerd to inject Envoy sidecar containers or Vault to inject secret volumes).

### Phase 2: Validating Admission Controllers
* **What they do:** Inspect the final object and either **accept** or **reject** the request with an error message. They **cannot** modify the object.
* **Execution Order:** Run **in parallel** (since they only read the object). If *any single* validating controller rejects the request, the entire API call fails immediately.
* **Examples:**
  * `NamespaceLifecycle`: Prevents creating Pods inside a namespace that does not exist, or inside a namespace currently in `Terminating` state, and blocks deleting built-in namespaces (`default`, `kube-system`, `kube-public`).
  * `ResourceQuota`: Rejects Pod creation if the namespace has exceeded its allocated CPU, memory, or object count limits.
  * `ValidatingAdmissionPolicy` / `ValidatingAdmissionWebhook`: Enforces custom organizational policies (e.g., blocking images from untrusted registries or banning `:latest` tags).

## 3. Common Built-In Admission Controllers

Kubernetes ships with dozens of built-in admission controllers enabled by default:

| Admission Controller | Type | Purpose |
| :--- | :--- | :--- |
| **`NamespaceLifecycle`** | Validating | Prevents operations in non-existent or `Terminating` namespaces; protects `kube-system`, `default`, and `kube-public`. |
| **`LimitRanger`** | Mutating & Validating | Enforces min/max container resource bounds and injects default `requests`/`limits` defined in a `LimitRange`. |
| **`ResourceQuota`** | Validating | Ensures total resource usage in a namespace never exceeds the namespace's `ResourceQuota`. |
| **`ServiceAccount`** | Mutating & Validating | Automatically attaches the `default` ServiceAccount (and mounts its token) to Pods that don't specify one. |
| **`DefaultStorageClass`** | Mutating | Assigns the default `StorageClass` to `PersistentVolumeClaims` without an explicit `storageClassName`. |
| **`DefaultTolerationSeconds`** | Mutating | Automatically adds default `300s` tolerations for `not-ready:NoExecute` and `unreachable:NoExecute` to Pods. |
| **`Priority`** | Mutating & Validating | Resolves `spec.priorityClassName` into its numeric `spec.priority` value and rejects invalid PriorityClass names. |
| **`NodeRestriction`** | Validating | Restricts a node's `kubelet` so it can only modify its own `Node` object and Pods bound specifically to itself. |
| **`TaintNodesByCondition`** | Mutating | Automatically taints newly joined nodes as `node.kubernetes.io/not-ready:NoSchedule` until ready. |
| **`NamespaceAutoProvision`** | Mutating | *(Disabled by default)* Automatically creates a namespace if a resource is deployed to a non-existent namespace. |

## 4. Inspecting Enabled Admission Controllers (`kubeadm` Cluster)

Because admission controllers are compiled directly into `kube-apiserver`, you check which ones are active by inspecting the `kube-apiserver` Static Pod or running a help query inside its container.

### Method 1: Check `kube-apiserver` Static Pod Flags

```bash
# View the --enable-admission-plugins flag in the kube-apiserver manifest
grep -i admission /etc/kubernetes/manifests/kube-apiserver.yaml
```

Typical output on a `kubeadm` cluster:
```text
    - --enable-admission-plugins=NodeRestriction
```
*(Note: Kubernetes automatically enables its standard recommended set of admission plugins behind the scenes; `--enable-admission-plugins` lists additional plugins enabled on top of the defaults).*

### Method 2: View All Default-Enabled Admission Plugins

Run `kube-apiserver -h` inside the running `kube-apiserver` container to see the exact list of plugins enabled and disabled by default in your Kubernetes version:

```bash
kubectl exec -n kube-system kube-apiserver-$(hostname) -- kube-apiserver -h | grep "enable-admission-plugins"
```

## 5. Enabling or Disabling Admission Controllers

To enable an optional built-in controller (such as `NamespaceAutoProvision`) or disable a default one (such as `DefaultStorageClass`), edit `/etc/kubernetes/manifests/kube-apiserver.yaml`.

### Step 1: Back Up the Manifest (Outside `/etc/kubernetes/manifests/`)

```bash
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
```

### Step 2: Update `--enable-admission-plugins` / `--disable-admission-plugins`

Edit `/etc/kubernetes/manifests/kube-apiserver.yaml` and update the command flags inside `spec.containers[0].command`:

```yaml
spec:
  containers:
    - command:
        - kube-apiserver
        - --advertise-address=10.97.0.20
        # ... other existing flags ...
        - --enable-admission-plugins=NodeRestriction,NamespaceAutoProvision
        - --disable-admission-plugins=DefaultStorageClass
      image: registry.k8s.io/kube-apiserver:v1.37.0
      name: kube-apiserver
```

* **`--enable-admission-plugins`**: Comma-separated list of additional admission plugins to turn **on**.
* **`--disable-admission-plugins`**: Comma-separated list of default admission plugins to turn **off**.
* Once you save `/etc/kubernetes/manifests/kube-apiserver.yaml`, `kubelet` automatically restarts `kube-apiserver` within a few seconds.

### Step 3: Verify `kube-apiserver` Restarted Cleanly

```bash
# Wait ~15-30 seconds, then verify the API server is responding
kubectl get pods -n kube-system -l component=kube-apiserver
kubectl get nodes
```

*(If `kube-apiserver` fails to start due to a typo in a plugin name, restore `/root/kube-apiserver.yaml.bak` back to `/etc/kubernetes/manifests/kube-apiserver.yaml`).*

## 6. Dynamic Admission Control (Extending Without Recompiling)

Because built-in admission controllers require recompiling `kube-apiserver` to add new logic, Kubernetes provides **Dynamic Admission Control** so you can enforce custom policies at runtime:

1. **ValidatingAdmissionPolicy (CEL — Built-In, No External Server Needed):**
   * Uses Common Expression Language (CEL) rules directly inside Kubernetes manifests (`ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding`) to validate objects in-process without running an external webhook server.
2. **Admission Webhooks (`MutatingWebhookConfiguration` & `ValidatingWebhookConfiguration`):**
   * Sends an HTTPS `AdmissionReview` JSON payload to an external HTTP service running inside or outside the cluster (used by policy engines like **OPA Gatekeeper**, **Kyverno**, and **cert-manager**).