# Kubernetes DaemonSet YAML & Architecture Guide

A **DaemonSet** ensures that **all (or a selected subset of) Nodes** in a Kubernetes cluster run a single copy of a specific Pod.

* **When a new Node joins the cluster:** The DaemonSet controller automatically schedules a copy of the Pod onto that new node.
* **When a Node is removed from the cluster:** Those Pods are garbage-collected automatically.
* **Deleting a DaemonSet:** Cleans up all Pods it created across every node.

> **Key Difference from Deployments/ReplicaSets:** A Deployment runs a fixed number of replicas (`replicas: 3`) distributed anywhere in the cluster. A DaemonSet does **not** have a `replicas` field—it automatically scales to match the number of eligible nodes ($1$ Pod per node).

## Common Real-World Use Cases

DaemonSets are primarily used for node-level infrastructure services that must run on every machine:

1. **Cluster Networking Plugins (CNI):** Such as `calico-node` (which you installed earlier in `kube-system`), Flannel, or Cilium.
2. **Log Collection Agents:** Such as Fluentd, Fluent Bit, or Promtail running on each node to ship container logs to centralized storage.
3. **Node Monitoring Daemons:** Such as Prometheus Node Exporter or Datadog Agent collecting host CPU, memory, and disk metrics.
4. **Cluster Storage Daemons:** Such as Ceph or GlusterFS agents.

## Complete `daemonset.yaml` Example

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentbit-logger
  namespace: kube-system
  labels:
    app: fluentbit
    tier: logging
spec:
  selector:
    matchLabels:
      app: fluentbit
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: fluentbit
    spec:
      tolerations:
        # Allows the DaemonSet Pod to also run on control-plane nodes
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: fluentbit
          image: fluent/fluent-bit:3.1
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"
            limits:
              memory: "128Mi"
              cpu: "250m"
          volumeMounts:
            - name: varlog
              mountPath: /var/log
              readOnly: true
      volumes:
        - name: varlog
          hostPath:
            path: /var/log
```

## Statement-by-Statement Explanation

### 1. Top-Level Fields

* **`apiVersion: apps/v1`**
  * **What it does:** Specifies the `apps/v1` API group, which governs workload controllers (`DaemonSet`, `Deployment`, `ReplicaSet`, `StatefulSet`).
* **`kind: DaemonSet`**
  * **What it does:** Declares that this manifest creates a **DaemonSet** controller.

### 2. `metadata` Section

* **`metadata:`**
  * **What it does:** Identifies the DaemonSet object.
* **`name: fluentbit-logger`**
  * **What it does:** Sets the DaemonSet's name. Each Pod created on a node will be named `fluentbit-logger-<random-5-char-hash>`.
* **`namespace: kube-system`**
  * **What it does:** Places the DaemonSet in `kube-system` (standard practice for cluster-wide system/logging agents, though they can run in any namespace).

### 3. `spec` Section (DaemonSet Behavior)

* **`spec:`**
  * **What it does:** Defines the desired state and update rules for the DaemonSet.
  * *(Notice there is **no** `replicas` field—the count is strictly determined by matching nodes).*
* **`selector.matchLabels:`**
  * **What it does:** Matches Pods labeled `app: fluentbit` so the DaemonSet controller knows which Pods belong to it. Must match `spec.template.metadata.labels`.
* **`updateStrategy:`**
  * **What it does:** Controls how DaemonSet Pods are updated when you modify `spec.template` (e.g., upgrading the container image):
    * **`type: RollingUpdate`** *(Default)*: Terminates old DaemonSet Pods and creates new ones one node at a time (`maxUnavailable: 1` ensures at most $1$ node loses its daemon Pod during an upgrade).
    * **`type: OnDelete`**: Old Pods are **not** replaced automatically when the manifest changes; new Pods are only created when you manually delete existing Pods on each node.

### 4. `template` Section (Pod Blueprint, Tolerations & Host Access)

* **`tolerations:`**
  * **Why it's critical for DaemonSets:** By default, control-plane nodes have the taint `node-role.kubernetes.io/control-plane:NoSchedule`. Without this toleration, the DaemonSet will only deploy Pods on worker nodes and skip your control-plane node.
* **`volumes` & `volumeMounts` (`hostPath`):**
  * **What it does:** DaemonSets frequently mount directories directly from the underlying host node's filesystem (such as `/var/log`) using `hostPath` so the container can read node/container logs or metrics.

## Running a DaemonSet on a Subset of Nodes

If you only want a DaemonSet to run on specific nodes (for example, only nodes with SSDs or GPUs), add **`nodeSelector`** or **`nodeAffinity`** inside `spec.template.spec`:

```yaml
  template:
    metadata:
      labels:
        app: gpu-monitor
    spec:
      nodeSelector:
        hardware: gpu
      containers:
        - name: gpu-exporter
          image: nvidia/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04
```

* With `nodeSelector` defined, the DaemonSet automatically places 1 Pod on every node carrying `hardware=gpu`, and ignores all other nodes.

## How DaemonSets Are Scheduled

* **Modern Kubernetes ($v1.12+$):** DaemonSet Pods are scheduled by the default **`kube-scheduler`** using built-in `NodeAffinity` rules (`metadata.name` matching each target node) and automatic tolerations for unschedulable node conditions (like `disk-pressure` or `memory-pressure`) so vital system agents aren't evicted when a node gets busy.

## Essential `kubectl` Commands for DaemonSets

```bash
# Create or update a DaemonSet
kubectl apply -f daemonset.yaml

# List DaemonSets in the current namespace (shows DESIRED, CURRENT, READY, UP-TO-DATE, AVAILABLE)
kubectl get daemonsets   # or: kubectl get ds

# View system DaemonSets (like calico-node and kube-proxy) in kube-system
kubectl get ds -n kube-system

# Verify that exactly 1 Pod is running per node
kubectl get pods -n kube-system -o wide

# Inspect DaemonSet configuration, node selector, and events
kubectl describe ds fluentbit-logger -n kube-system

# Check rollout status during an image update
kubectl rollout status daemonset/fluentbit-logger -n kube-system

# Delete a DaemonSet and all its Pods across all nodes
kubectl delete -f daemonset.yaml
```