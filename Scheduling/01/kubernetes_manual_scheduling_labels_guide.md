# Kubernetes Scheduling & Organization: Manual Scheduling, Labels & Selectors

This README covers core Kubernetes scheduling and resource-grouping concepts: **Manual Scheduling** (assigning Pods to specific nodes without a scheduler) and **Labels & Selectors** (organizing, filtering, and connecting Kubernetes objects).

---

## Part 1: Manual Scheduling

Normally, the **kube-scheduler** automatically watches for unscheduled Pods (where `spec.nodeName` is empty) and assigns them to the best available node based on resource requirements, taints, and affinity rules.

However, if no scheduler is running in your cluster—or if you want to pin a Pod directly to a specific node for testing or troubleshooting—you can schedule it manually in two ways.

### Method 1: Setting `nodeName` at Pod Creation

If the Pod has **not yet been created**, you can specify the exact target node name directly inside `spec.nodeName` in your Pod YAML manifest.

#### Example `manual-pod.yaml`
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-manual
  labels:
    app: nginx
spec:
  nodeName: worker-node-01
  containers:
    - name: nginx-container
      image: nginx:1.27
      ports:
        - containerPort: 80
```

* **How it works:** When applied (`kubectl apply -f manual-pod.yaml`), the `kubelet` running on `worker-node-01` immediately sees a Pod assigned to its node name and starts the container—completely bypassing `kube-scheduler`.
* **Limitation:** Kubernetes does **not** allow modifying `spec.nodeName` on an already-running or pending Pod (`nodeName` is immutable after creation).

---

### Method 2: Creating a `Binding` Object (For Existing `Pending` Pods)

If a Pod **already exists** in a `Pending` state because `kube-scheduler` is down or missing, you cannot edit `spec.nodeName` directly. Instead, you mimic what the scheduler does behind the scenes by sending a **`Binding`** object to the Pod's `/binding` API endpoint.

#### Example `pod-bind.yaml`
```yaml
apiVersion: v1
kind: Binding
metadata:
  name: nginx-manual
target:
  apiVersion: v1
  kind: Node
  name: worker-node-01
```

#### Applying the Binding via API (`curl` or `kubectl replace`)
Because `Binding` cannot be applied with a standard `kubectl apply`, you submit it directly to the Pod's `/binding` subresource:

```bash
# Using kubectl replace --raw
kubectl replace --raw /api/v1/namespaces/default/pods/nginx-manual/binding -f pod-bind.yaml
```

* **`metadata.name`**: Must match the exact name of the `Pending` Pod (`nginx-manual`).
* **`target.name`**: The exact name of the target node (`worker-node-01`).

### Lab Verification Commands
```bash
# Check available node names in your cluster
kubectl get nodes

# Verify which node a Pod is scheduled on
kubectl get pods -o wide

# Inspect scheduler Pods in kube-system (to check if a scheduler is running)
kubectl get pods -n kube-system
```

---

## Part 2: Labels, Selectors, and Annotations

As clusters grow to hundreds of Pods, Services, and Deployments, **Labels** and **Selectors** provide the primary mechanism to group, filter, and link resources together.

### 1. Labels

**Labels** are arbitrary key-value pairs attached to Kubernetes objects under `metadata.labels`. They identify meaningful attributes for users and controllers (such as environment, tier, version, or team) without directly affecting how the container runs.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: frontend-pod
  labels:
    app: web-store
    tier: frontend
    environment: prod
    version: v1.2
spec:
  containers:
    - name: nginx
      image: nginx:1.27
```

* **Syntax Rules:**
  * Keys and values can be up to $63$ characters long.
  * Must begin and end with an alphanumeric character (`[a-z0-9A-Z]`), with dashes (`-`), underscores (`_`), or dots (`.`) allowed in between.

---

### 2. Selectors

**Selectors** allow users (via `kubectl`) and Kubernetes controllers (`ReplicaSet`, `Deployment`, `Service`) to filter and match objects based on their labels.

#### A. Imperative Filtering with `kubectl` (`-l` / `--selector`)

```bash
# Equality-based selector: find Pods where app=web-store
kubectl get pods -l app=web-store

# Multiple conditions (AND logic): app=web-store AND tier=frontend
kubectl get pods -l app=web-store,tier=frontend

# Inequality selector: find Pods where environment is NOT prod
kubectl get pods -l environment!=prod

# Set-based selector: find Pods where environment is either dev or staging
kubectl get pods -l 'environment in (dev, staging)'

# Set-based exclusion: find Pods where tier is NOT backend or db
kubectl get pods -l 'tier notin (backend, db)'

# Display all labels as columns in kubectl output
kubectl get pods --show-labels
```

#### B. Declarative Selectors in YAML (`matchLabels` & `matchExpressions`)

Controllers like `Deployment` and `ReplicaSet` use `spec.selector` to adopt and manage Pods:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-store
      tier: frontend
    matchExpressions:
      - key: environment
        operator: In
        values:
          - prod
          - staging
  template:
    metadata:
      labels:
        app: web-store
        tier: frontend
        environment: prod
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
```

* **`matchLabels`**: Requires every specified key-value pair to match exactly (`AND` logic).
* **`matchExpressions`**: Supports advanced set-based operators:
  * `In`: Label value must match one of the listed values.
  * `NotIn`: Label value must not match any of the listed values.
  * `Exists`: Label key must exist on the object (regardless of value).
  * `DoesNotExist`: Label key must not exist on the object.

*(Note: `Service` manifests only support simple key-value equality under `spec.selector` and do not use `matchLabels` or `matchExpressions`).*

---

### 3. Annotations (Quick Comparison)

While **Labels** are used to *identify and select* objects, **Annotations** (`metadata.annotations`) attach non-identifying metadata for humans, tooling, or external integrations (such as build numbers, Git commit hashes, contact info, or Ingress controller rules).

```yaml
metadata:
  name: frontend-pod
  labels:
    app: web-store
  annotations:
    build-version: "2026.11.19-rc1"
    maintainer: "platform-team@example.com"
```

| Feature | Labels | Annotations |
| :--- | :--- | :--- |
| **Purpose** | Grouping, selecting, and connecting objects | Storing rich non-identifying metadata |
| **Queryable via Selectors?** | Yes (`-l key=value`) | No |
| **Size / Character Limits** | Strict ($63$ chars max per key/value) | Flexible (supports large strings, JSON, URLs) |

---

## Quick Label Management Commands

```bash
# Add a new label to an existing Pod
kubectl label pod frontend-pod release=canary

# Overwrite an existing label value (--overwrite is required)
kubectl label pod frontend-pod environment=staging --overwrite

# Remove a label from a Pod (append a minus sign '-' to the key)
kubectl label pod frontend-pod release-
```