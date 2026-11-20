# Kubernetes PriorityClasses & Pod Preemption Guide

In a Kubernetes cluster with limited CPU and memory, **PriorityClasses** indicate the relative importance of a Pod compared to other Pods.

When a cluster runs out of resources to schedule a newly created Pod, the **`kube-scheduler`** uses PriorityClasses to:
1. **Order the scheduling queue:** Higher-priority Pods are placed ahead of lower-priority Pods in the pending queue.
2. **Trigger Preemption (Eviction):** If no node has enough free resources to run a high-priority Pod, the scheduler can **preempt (evict)** lower-priority Pods from a node to free up capacity for the high-priority Pod.

---

## 1. How Priority Values Work

A `PriorityClass` is a **cluster-scoped** (non-namespaced) object that maps a human-readable name to an integer `value`.

* **Higher integer = Higher priority.**
* **User-defined values:** Can be any $32$-bit integer less than or equal to $1{,}000{,}000{,}000$ ($1\text{ billion}$), including negative numbers (e.g., `-10` for low-priority batch jobs).
* **System-reserved values:** Values above $1{,}000{,}000{,}000$ are reserved exclusively for critical Kubernetes system components.
* **Default Priority:** If a Pod does not specify a `priorityClassName`, its priority defaults to **`0`** (unless a PriorityClass is marked with `globalDefault: true`).

---

## 2. Built-In System PriorityClasses

Kubernetes ships with two built-in PriorityClasses used by critical control-plane and node components (such as `coredns`, `kube-proxy`, and `calico-node`):

1. **`system-cluster-critical`** (`value: 2000000000`)
   * Used for cluster-wide critical add-ons like CoreDNS.
2. **`system-node-critical`** (`value: 2000001000`)
   * Highest possible priority in the cluster; used for critical node-level daemons that must never be evicted unless absolutely unavoidable.

---

## 3. Complete `priorityclass.yaml` Example

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority-apps
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: "Used for mission-critical production application Pods."
```

### Statement-by-Statement Breakdown

* **`apiVersion: scheduling.k8s.io/v1`**
  * **What it does:** Specifies the `scheduling.k8s.io/v1` API group where `PriorityClass` resources live.
* **`kind: PriorityClass`**
  * **What it does:** Declares a cluster-scoped `PriorityClass` definition.
* **`metadata.name: high-priority-apps`**
  * **What it does:** Sets the unique name Pods will reference via `spec.priorityClassName`.
* **`value: 1000000`**
  * **What it does:** Assigns a numeric priority of $1{,}000{,}000$ (higher than default Pods at $0$, but safely below system-critical Pods at $2{,}000{,}000{,}000$).
* **`globalDefault: false`** *(Optional)*
  * **What it does:** Controls whether this PriorityClass is automatically assigned to Pods that do **not** specify a `priorityClassName`.
  * **Rule:** Only **one** PriorityClass in the entire cluster can have `globalDefault: true`. Changing it affects only newly created Pods, not existing ones.
* **`preemptionPolicy: PreemptLowerPriority`** *(Optional)*
  * **What it does:** Controls whether Pods with this PriorityClass are allowed to evict lower-priority Pods when resources are scarce:
    * **`PreemptLowerPriority`** *(Default)*: Allows the Pod to preempt (evict) lower-priority Pods on a node to make room for itself.
    * **`Never`**: Places the Pod ahead of lower-priority Pods in the scheduling queue, **but** prevents it from evicting already-running lower-priority Pods (it will wait until resources free up naturally).
* **`description:`**
  * **What it does:** Human-readable explanation of when operators and developers should use this PriorityClass.

---

## 4. Assigning a PriorityClass to a Pod (or Deployment)

To assign a PriorityClass to a workload, reference its `metadata.name` under `spec.priorityClassName` in your Pod manifest (or `spec.template.spec.priorityClassName` in a Deployment/DaemonSet):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: payment-service-pod
  labels:
    app: payment-service
spec:
  priorityClassName: high-priority-apps
  containers:
    - name: payment-container
      image: nginx:1.27
      resources:
        requests:
          memory: "256Mi"
          cpu: "500m"
```

* When submitted to the API server, the **Priority Admission Controller** looks up `high-priority-apps` and populates the Pod's integer `spec.priority` field (`1000000`).
* If you reference a `priorityClassName` that does **not** exist in the cluster, the API server **rejects** the Pod creation immediately.

---

## 5. How Preemption Works Step-by-Step

Suppose a node is completely full running three low-priority Pods (`priority: 0`), and a new `high-priority-apps` Pod (`priority: 1000000`) is created:

1. **Scheduling Attempt Fails:** The scheduler sees no node has enough unallocated CPU/memory (`requests`) to fit the new Pod.
2. **Preemption Evaluation:** Because `preemptionPolicy` is `PreemptLowerPriority`, the scheduler checks which node could fit the new Pod if lower-priority Pods were removed.
3. **Victim Selection & Eviction:** The scheduler selects the node requiring the least disruption, gracefully terminates (evicts) the necessary lower-priority Pods, and sets `nominatedNodeName` on the high-priority Pod.
4. **Pod Placement:** Once the evicted Pods finish terminating and free their resources, the high-priority Pod is scheduled onto that node.

> **Important Note on PodDisruptionBudgets (PDBs):** The scheduler tries to respect `PodDisruptionBudget` rules during preemption, though if no alternative exists, a high-priority Pod can still preempt Pods even if it violates a PDB.

---

## 6. Essential `kubectl` Commands

```bash
# Create the PriorityClass from YAML
kubectl apply -f priorityclass.yaml

# Create a PriorityClass imperatively in one line
kubectl create priorityclass low-priority-batch --value=-10 --description="Batch jobs"

# List all PriorityClasses (including built-in system ones)
kubectl get priorityclasses   # or: kubectl get pc

# Inspect details of a specific PriorityClass
kubectl describe pc high-priority-apps

# Check the resolved numeric priority and priorityClassName of running Pods
kubectl get pods -o custom-columns=NAME:.metadata.name,PRIORITY_CLASS:.spec.priorityClassName,PRIORITY:.spec.priority

# Delete a PriorityClass
kubectl delete pc high-priority-apps
```