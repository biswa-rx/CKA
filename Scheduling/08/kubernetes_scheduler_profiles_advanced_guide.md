# Configuring Kubernetes Scheduler Profiles: Detailed & Advanced Guide

In earlier Kubernetes versions, running different scheduling behaviors (e.g., high-density bin-packing for batch jobs vs. high-availability spreading for web apps) required deploying completely separate `kube-scheduler` binaries. That approach wasted memory, duplicated cluster state caches, and risked race conditions where two schedulers tried to claim the same node resources simultaneously.

**Scheduler Profiles** (`kubescheduler.config.k8s.io/v1`) solve this by allowing a **single `kube-scheduler` process** to expose multiple distinct scheduler personalities—each with its own `schedulerName`, plugin pipeline, and scoring weights—sharing a single unified cluster cache and scheduling queue.

---

## 1. Architecture: How Scheduler Profiles Work Internally

A single `kube-scheduler` instance executes a **Scheduling Cycle** (serial, one Pod at a time) followed by a **Binding Cycle** (concurrent). Every Pod entering the scheduling queue carries a `spec.schedulerName` that routes it to the matching **Profile** inside `KubeSchedulerConfiguration`.

```
                    +-------------------------------------------+
                    |        Single kube-scheduler Binary       |
                    |                                           |
Pod (default)  ---> |  Profile 1: default-scheduler             |
                    |   [QueueSort -> Filter -> Score -> Bind]  | ---> Shared Node Cache
Pod (binpack)  ---> |  Profile 2: bin-packing-scheduler         |      & API Binding
                    |   [QueueSort -> Filter -> Score -> Bind]  |
                    +-------------------------------------------+
```

### Key Architectural Benefits
* **Zero Race Conditions:** Both profiles read and update the exact same in-memory node resource snapshot (`assumed` Pods), preventing double-booking of CPU/memory.
* **Lower Control-Plane Overhead:** Only one `kube-scheduler` Pod, one API server watch stream, and one leader-election `Lease` are needed.
* **Per-Profile Plugin Tuning:** Each profile can independently enable, disable, or re-weight plugins at specific **Extension Points**.

---

## 2. The Scheduling Framework & Extension Points

To configure profiles at an advanced level, you must understand the **11 Extension Points** executed in order for every Pod:

### Phase A: Scheduling Cycle (Synchronous)
1. **`queueSort`**: Orders Pods waiting in the active scheduling queue (Default plugin: `PrioritySort`). *Note: Because there is only one shared queue per scheduler binary, all profiles in a single configuration must share the exact same `queueSort` plugin.*
2. **`preFilter`**: Pre-processes Pod info or checks cluster-wide preconditions before evaluating individual nodes (e.g., `NodeResourcesFit`, `InterPodAffinity`, `VolumeBinding`). If `preFilter` fails, the Pod is rejected immediately without checking nodes.
3. **`filter`** *(Predicates)*: Eliminates nodes that cannot run the Pod (e.g., insufficient CPU/RAM via `NodeResourcesFit`, unmatched `NodeAffinity`, un-tolerated `TaintToleration`, or `NodeUnschedulable`).
4. **`postFilter`**: Runs **only** if zero nodes pass the `filter` phase. Responsible for **Preemption** (`DefaultPreemption` plugin), which evicts lower-priority Pods to make room.
5. **`preScore`**: Generates shared state across feasible nodes before scoring begins.
6. **`score`** *(Priorities)*: Ranks every feasible node that passed `filter` with an integer score between `0` and `100`.
7. **`normalizeScore`**: Scales raw plugin scores into the standardized `[0, 100]` range before multiplying each plugin's score by its configured `weight`.
8. **`reserve`**: Optimistically reserves resources for the Pod on the highest-scoring winning node in the scheduler's local cache before the actual API binding happens.

### Phase B: Binding Cycle (Asynchronous)
9. **`permit`**: Can approve, deny, or hold a Pod in a waiting state (used for gang scheduling / co-scheduling where all Pods in a job must wait until enough nodes are reserved).
10. **`preBind`**: Performs prerequisite actions before binding—most notably **`VolumeBinding`**, which provisions and binds PersistentVolumeClaims (`PVCs`) to the chosen node.
11. **`bind`**: Writes the `Binding` object to the Kubernetes API server (`DefaultBinder` plugin), officially assigning `spec.nodeName` to the Pod.
12. **`postBind`**: Informational hook executed after successful binding (useful for metrics/auditing).

---

## 3. Built-In Default Plugins Reference

Out of the box, the `default-scheduler` profile enables these core plugins:

| Plugin Name | Extension Points | Purpose |
| :--- | :--- | :--- |
| **`PrioritySort`** | `queueSort` | Sorts pending Pods by `PriorityClass` value. |
| **`NodeUnschedulable`** | `filter` | Filters out nodes with `spec.unschedulable: true` (`kubectl cordon`). |
| **`NodeName`** | `filter` | Checks if `spec.nodeName` matches the candidate node. |
| **`TaintToleration`** | `filter`, `score` | Enforces `NoSchedule` taints (`filter`) and penalizes `PreferNoSchedule` taints (`score`). |
| **`NodeAffinity`** | `filter`, `score` | Enforces `requiredDuringScheduling...` (`filter`) and scores `preferredDuringScheduling...` (`score`). |
| **`NodeResourcesFit`** | `preFilter`, `filter`, `score` | Checks CPU/Memory `requests` (`filter`) and scores nodes using `LeastAllocated`, `MostAllocated`, or `RequestedToCapacityRatio` (`score`). |
| **`NodeResourcesBalancedAllocation`** | `score` | Favors nodes where CPU and memory utilization percentages stay balanced. |
| **`InterPodAffinity`** | `preFilter`, `filter`, `preScore`, `score` | Enforces Pod-to-Pod affinity and anti-affinity rules. |
| **`PodTopologySpread`** | `preFilter`, `filter`, `preScore`, `score` | Spreads Pods evenly across failure domains (zones, regions, hostnames). |
| **`VolumeBinding`** | `preFilter`, `filter`, `reserve`, `preBind` | Ensures PersistentVolumes exist in the node's zone and binds dynamic PVCs. |
| **`ImageLocality`** | `score` | Prefers nodes that already have the container image cached locally. |
| **`DefaultPreemption`** | `postFilter` | Evicts lower-priority Pods when no feasible node is found. |
| **`DefaultBinder`** | `bind` | Binds the Pod to the selected node via the Kubernetes API. |

---

## 4. Advanced Multi-Profile Configuration (`KubeSchedulerConfiguration`)

Below is an advanced `KubeSchedulerConfiguration` defining **three distinct profiles** inside one `kube-scheduler` instance:

1. **`default-scheduler`**: Standard balanced scheduling behavior.
2. **`bin-packing-scheduler`**: Packs Pods tightly onto as few nodes as possible (`MostAllocated` strategy) so idle nodes can scale down—ideal for batch/CI workloads.
3. **`no-preemption-scheduler`**: Disables `DefaultPreemption` and uses `DefaultBinder` with custom scoring weights—ideal for best-effort workloads that must never evict existing Pods.

### Complete `scheduler-profiles-config.yaml`

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
leaderElection:
  leaderElect: true
  resourceNamespace: kube-system
  resourceName: kube-scheduler
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf
profiles:
  # Profile 1: Standard Default Scheduler
  - schedulerName: default-scheduler

  # Profile 2: High-Density Bin-Packing Scheduler (MostAllocated)
  - schedulerName: bin-packing-scheduler
    plugins:
      score:
        disabled:
          # Disable default LeastAllocated / BalancedAllocation behavior
          - name: NodeResourcesBalancedAllocation
          - name: ImageLocality
        enabled:
          # Explicitly re-enable NodeResourcesFit with high weight
          - name: NodeResourcesFit
            weight: 10
    pluginConfig:
      - name: NodeResourcesFit
        args:
          scoringStrategy:
            type: MostAllocated
            resources:
              - name: cpu
                weight: 1
              - name: memory
                weight: 2

  # Profile 3: Non-Preempting Latency-Sensitive Scheduler
  - schedulerName: no-preemption-scheduler
    plugins:
      postFilter:
        disabled:
          # Prevents this profile from ever evicting lower-priority Pods
          - name: DefaultPreemption
      score:
        enabled:
          # Heavily favor nodes that already have the container image cached
          - name: ImageLocality
            weight: 50
          - name: PodTopologySpread
            weight: 20
```

---

## 5. Deep Dive into Configuration Statements

### `plugins.<extensionPoint>.disabled` & `enabled`
* **`disabled`**: Removes specific default plugins from that extension point for this profile only.
  * *Wildcard Trick:* Use `- name: "*"` under `disabled` to disable **every** default plugin at that extension point, then list only the exact plugins you want under `enabled`.
* **`enabled`**: Adds custom plugins or overrides the `weight` of an existing plugin at the `score` extension point.
  * **Weights:** Must be positive integers. If a plugin is already enabled by default, listing it under `enabled` updates its `weight` without duplicating it.

### `pluginConfig` (Fine-Tuning Plugin Arguments)
Many built-in plugins accept structured configuration arguments under `pluginConfig`:

1. **`NodeResourcesFit` (`scoringStrategy`)**:
   * **`LeastAllocated`** *(Default)*: Prefers nodes with the *most* free CPU/memory (spreads load across nodes).
   * **`MostAllocated`**: Prefers nodes with the *highest* utilization (packs Pods onto fewer nodes to save cloud compute costs).
   * **`RequestedToCapacityRatio`**: Allows defining a custom `shape` curve mapping utilization percentages (`0–100`) to custom scores (`0–10`).
2. **`PodTopologySpread` (`defaultConstraints`)**:
   * Allows setting cluster-wide default `topologySpreadConstraints` (e.g., `maxSkew: 1` across `topology.kubernetes.io/zone`) for Pods that do not define their own constraints.
3. **`VolumeBinding` (`bindTimeoutSeconds`)**:
   * Sets how long (`default: 600s`) the scheduler waits for dynamic PVC provisioning before timing out.

---

## 6. Applying Custom Scheduler Profiles on a `kubeadm` Cluster

On a `kubeadm` cluster, `kube-scheduler` runs as a **Static Pod** defined in `/etc/kubernetes/manifests/kube-scheduler.yaml`. Follow these steps carefully to configure custom profiles on your control-plane node:

### Step 1: Save the `KubeSchedulerConfiguration` File on the Control Plane
Create a dedicated directory and save your profile configuration file:

```bash
sudo mkdir -p /etc/kubernetes/scheduler
cat <<EOF | sudo tee /etc/kubernetes/scheduler/scheduler-profiles-config.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
leaderElection:
  leaderElect: true
  resourceNamespace: kube-system
  resourceName: kube-scheduler
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf
profiles:
  - schedulerName: default-scheduler
  - schedulerName: bin-packing-scheduler
    plugins:
      score:
        disabled:
          - name: NodeResourcesBalancedAllocation
        enabled:
          - name: NodeResourcesFit
            weight: 10
    pluginConfig:
      - name: NodeResourcesFit
        args:
          scoringStrategy:
            type: MostAllocated
            resources:
              - name: cpu
                weight: 1
              - name: memory
                weight: 1
EOF
```

### Step 2: Back Up and Update `/etc/kubernetes/manifests/kube-scheduler.yaml`
Always back up the static manifest outside `/etc/kubernetes/manifests/` first (never place backups inside `/etc/kubernetes/manifests/`, or `kubelet` will try to run both!).

```bash
sudo cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak
```

Edit `/etc/kubernetes/manifests/kube-scheduler.yaml` to:
1. Add `--config=/etc/kubernetes/scheduler/scheduler-profiles-config.yaml` to `spec.containers[0].command` (removing conflicting CLI flags like `--leader-elect=true` or `--kubeconfig=...` that are now defined inside `scheduler-profiles-config.yaml`).
2. Mount `/etc/kubernetes/scheduler` into the `kube-scheduler` container via `volumeMounts` and `volumes`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    component: kube-scheduler
    tier: control-plane
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
    - command:
        - kube-scheduler
        - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
        - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
        - --bind-address=127.0.0.1
        - --config=/etc/kubernetes/scheduler/scheduler-profiles-config.yaml
      image: registry.k8s.io/kube-scheduler:v1.37.0
      name: kube-scheduler
      volumeMounts:
        - mountPath: /etc/kubernetes/scheduler.conf
          name: kubeconfig
          readOnly: true
        - mountPath: /etc/kubernetes/scheduler
          name: scheduler-config
          readOnly: true
  hostNetwork: true
  priorityClassName: system-node-critical
  volumes:
    - hostPath:
        path: /etc/kubernetes/scheduler.conf
        type: FileOrCreate
      name: kubeconfig
    - hostPath:
        path: /etc/kubernetes/scheduler
        type: DirectoryOrCreate
      name: scheduler-config
```

* Because `kube-scheduler` is a Static Pod, `kubelet` automatically restarts it within seconds of saving `/etc/kubernetes/manifests/kube-scheduler.yaml`.

---

## 7. Routing Workloads to Specific Profiles

Once the scheduler restarts cleanly, target any profile by setting **`spec.schedulerName`** in your Pod or Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-worker-binpacked
spec:
  replicas: 4
  selector:
    matchLabels:
      app: batch-worker
  template:
    metadata:
      labels:
        app: batch-worker
    spec:
      schedulerName: bin-packing-scheduler
      containers:
        - name: worker
          image: nginx:1.27
          resources:
            requests:
              cpu: "250m"
              memory: "128Mi"
```

---

## 8. Troubleshooting & Validation Checklist

```bash
# 1. Verify kube-scheduler Static Pod restarted and is Running
kubectl get pods -n kube-system -l component=kube-scheduler

# 2. Check scheduler startup logs for configuration syntax or plugin validation errors
kubectl logs -n kube-system -l component=kube-scheduler --tail=50

# 3. Deploy the bin-packing Deployment and inspect scheduling events
kubectl apply -f batch-deployment.yaml
kubectl get events --sort-by='.metadata.creationTimestamp' | grep Scheduled

# 4. If kube-scheduler fails to start due to a YAML typo, restore your backup immediately:
sudo cp /root/kube-scheduler.yaml.bak /etc/kubernetes/manifests/kube-scheduler.yaml
```

### Common Pitfalls to Avoid
1. **Duplicate CLI Flags vs. `--config`:** Passing `--leader-elect` on the command line while also defining `leaderElection` inside `KubeSchedulerConfiguration` causes `kube-scheduler` to exit immediately with a flag conflict error.
2. **Different `queueSort` Plugins Across Profiles:** All profiles in a single `KubeSchedulerConfiguration` *must* use the same `queueSort` plugin (`PrioritySort`), otherwise configuration validation fails at startup.
3. **Backup Files Inside `/etc/kubernetes/manifests/`:** Never leave `.bak` files inside `/etc/kubernetes/manifests/`; `kubelet` treats every file in that directory as an active Static Pod manifest.