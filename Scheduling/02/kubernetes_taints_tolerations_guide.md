# Kubernetes Taints and Tolerations Guide

**Taints** and **Tolerations** work together to ensure that Pods are not scheduled onto inappropriate nodes. 

* **Taints** are applied to **Nodes**—they act like a repellent that *pushes* Pods away unless a Pod explicitly has permission to land there.
* **Tolerations** are applied to **Pods**—they act like a pass that *allows* (but does **not** guarantee) a Pod to be scheduled onto a node with a matching taint.

> **Analogy:** Think of a **Taint** as bug spray applied to a person (the Node) to repel mosquitoes (Pods). A **Toleration** is immunity applied to a specific mosquito so it can still land on that person—while other mosquitoes without immunity stay away.

---

## 1. How Taints Work on Nodes

A taint consists of three parts: a **key**, an optional **value**, and an **effect**:

```text
<key>=<value>:<effect>
```

### The Three Taint Effects

1. **`NoSchedule`**
   * **Behavior:** New Pods that do **not** tolerate the taint will **not** be scheduled onto this node.
   * **Existing Pods:** Pods already running on the node before the taint was applied remain undisturbed.

2. **`PreferNoSchedule`**
   * **Behavior:** A "soft" version of `NoSchedule`. The scheduler tries to avoid placing non-tolerating Pods on the node, **but** if no other nodes have capacity, it will still schedule them there.
   * **Existing Pods:** Remain undisturbed.

3. **`NoExecute`**
   * **Behavior:** Strongest effect. New Pods without a matching toleration are **not** scheduled onto the node, **AND** any existing Pods already running on the node that do not tolerate the taint are **immediately evicted (terminated)**.
   * **Bonus Feature:** Pods with a matching `NoExecute` toleration can optionally specify `tolerationSeconds` to stay on the node for a fixed grace period before being evicted.

---

## 2. Managing Taints via `kubectl`

```bash
# 1. Add a taint to a node (restricts node to 'gpu' workloads)
kubectl taint nodes worker-node-01 hardware=gpu:NoSchedule

# 2. Add a key-only taint (no value)
kubectl taint nodes worker-node-01 dedicated:NoExecute

# 3. Inspect existing taints on a node
kubectl describe node worker-node-01 | grep -i taints
# Or view all nodes' taints in one command:
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# 4. Remove a taint (append a minus '-' sign at the end)
kubectl taint nodes worker-node-01 hardware=gpu:NoSchedule-
```

---

## 3. Adding Tolerations to Pods (YAML Examples)

To allow a Pod to be scheduled onto a tainted node, define `spec.tolerations` in your Pod (or Deployment `spec.template.spec`) manifest.

### Example 1: Exact Match (`operator: Equal`)

Matches a taint where both `key` and `value` match (`hardware=gpu:NoSchedule`).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ml-training-pod
spec:
  tolerations:
    - key: "hardware"
      operator: "Equal"
      value: "gpu"
      effect: "NoSchedule"
  containers:
    - name: cuda-container
      image: nvidia/cuda:12.4.0-base-ubuntu22.04
```

* **`key`**: `"hardware"` — Must match the taint's key.
* **`operator`**: `"Equal"` (default if omitted) — Requires the `value` field to match the taint's value exactly.
* **`value`**: `"gpu"` — Must match the taint's value.
* **`effect`**: `"NoSchedule"` — Must match the taint's effect (if omitted, matches *all* effects for that key/value).

---

### Example 2: Key-Only Match (`operator: Exists`)

Matches any taint with the key `"dedicated"`, regardless of its value (or if it has no value).

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: dedicated-app-pod
spec:
  tolerations:
    - key: "dedicated"
      operator: "Exists"
      effect: "NoExecute"
      tolerationSeconds: 3600
  containers:
    - name: nginx
      image: nginx:1.27
```

* **`operator: "Exists"`**: Do **not** specify a `value` field when using `Exists`.
* **`tolerationSeconds: 3600`**: If the `dedicated:NoExecute` taint is added while this Pod is running, Kubernetes allows the Pod to continue running for $3600\text{ seconds}$ ($1\text{ hour}$) before evicting it.

---

### Example 3: Catch-All Toleration (Tolerates Everything)

An empty `operator: "Exists"` with no `key` or `effect` tolerates **every taint** in the cluster (commonly used by system DaemonSets like CNI network plugins or log collectors that must run on every node):

```yaml
tolerations:
  - operator: "Exists"
```

---

## 4. Built-In Control-Plane & Node Taints

When you bootstrapped your cluster with `kubeadm init`, Kubernetes automatically placed a taint on your control-plane node so regular application Pods wouldn't consume control-plane resources:

```text
node-role.kubernetes.io/control-plane:NoSchedule
```

* **Why system pods still run there:** Control-plane pods (`kube-apiserver`, `etcd`, `calico-node`, `kube-proxy`) include a matching toleration for `node-role.kubernetes.io/control-plane:NoSchedule`.
* **Single-Node Cluster Tip:** If you are practicing on a single-node cluster and want regular Pods to schedule onto the control-plane node, you can remove that taint with:
  ```bash
  kubectl taint nodes --all node-role.kubernetes.io/control-plane-
  ```

### Automatic Node Condition Taints (`NoExecute`)
Kubernetes also automatically taints unhealthy nodes so workloads migrate away safely:
* `node.kubernetes.io/not-ready:NoExecute` — Node is unresponsive or `NotReady`.
* `node.kubernetes.io/unreachable:NoExecute` — Node is unreachable from the control plane.
* `node.kubernetes.io/disk-pressure:NoSchedule` — Node is running out of disk space.
* `node.kubernetes.io/memory-pressure:NoSchedule` — Node is running low on memory.

---

## 5. Crucial Caveat: Tolerations Do NOT Guarantee Placement!

A common misconception is that adding a toleration forces a Pod onto a tainted node:
* **Taints & Tolerations** only *repel* non-tolerating Pods from tainted nodes. A Pod with a `hardware=gpu` toleration can **still** be scheduled onto a regular, untainted worker node!
* To **guarantee** that a Pod lands *only* on the GPU node (and nowhere else), you combine **Taints & Tolerations** (to keep other Pods out) with **Node Selectors** or **Node Affinity** (to pull your Pod onto that specific node).