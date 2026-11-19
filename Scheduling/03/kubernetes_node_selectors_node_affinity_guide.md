# Kubernetes Node Selectors & Node Affinity Guide

While **Taints & Tolerations** *repel* Pods from nodes, **Node Selectors** and **Node Affinity** *attract* Pods to specific nodes based on node labels (such as hardware type, availability zone, or disk speed).

---

## Step 1: Labeling Nodes

Both `nodeSelector` and `nodeAffinity` rely on labels attached to your Kubernetes nodes.

```bash
# View existing labels on all nodes
kubectl get nodes --show-labels

# Add custom labels to a node
kubectl label nodes worker-node-01 size=Large disktype=ssd

# Remove a label from a node (append '-')
kubectl label nodes worker-node-01 size-
```

---

## Part 1: Node Selectors (`nodeSelector`)

`nodeSelector` is the simplest way to constrain a Pod to run only on nodes with specific labels.

### Complete `node-selector-pod.yaml` Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: data-processing-pod
spec:
  nodeSelector:
    size: Large
    disktype: ssd
  containers:
    - name: processor
      image: nginx:1.27
```

### How It Works & Limitations

* **Exact Match (`AND` logic):** The scheduler will only place this Pod on a node that has **both** `size=Large` **AND** `disktype=ssd`.
* **Hard Requirement:** If no node in the cluster has those exact labels, the Pod remains stuck in a **`Pending`** state.
* **Limitations:** `nodeSelector` only supports exact `key=value` equality. It cannot express `OR` conditions (`size=Large` OR `size=Medium`), `NOT` conditions (`size!=Small`), or soft preferences ("prefer Large nodes, but run elsewhere if none are available").

---

## Part 2: Node Affinity (`nodeAffinity`)

**Node Affinity** solves the limitations of `nodeSelector` by offering expressive matching operators (`In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt`) and distinguishing between **hard** requirements and **soft** preferences.

### The Two Types of Node Affinity Rules

1. **`requiredDuringSchedulingIgnoredDuringExecution`** *(Hard Rule)*
   * **During Scheduling:** The Pod **must** match the rule to be scheduled onto a node. If no matching node exists, the Pod stays `Pending`.
   * **During Execution:** If a node's labels change *after* the Pod is already running so that it no longer matches, Kubernetes **ignores** the change and leaves the Pod running.

2. **`preferredDuringSchedulingIgnoredDuringExecution`** *(Soft Rule / Weighted Preference)*
   * **During Scheduling:** The scheduler *tries* to find a node matching the rule (using `weight` from $1$ to $100$ to score nodes). However, if no matching node is available, the scheduler still places the Pod on another available node rather than leaving it `Pending`.
   * **During Execution:** Already-running Pods continue running undisturbed if node labels change.

*(Note: `RequiredDuringExecution`—which would evict running Pods if node labels change—is planned for future Kubernetes versions).*

### Complete `node-affinity-pod.yaml` Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: analytics-pod
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: size
                operator: In
                values:
                  - Large
                  - Medium
              - key: environment
                operator: NotIn
                values:
                  - dev
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 80
          preference:
            matchExpressions:
              - key: disktype
                operator: In
                values:
                  - ssd
  containers:
    - name: analytics-container
      image: nginx:1.27
```

---

## Statement-by-Statement Breakdown of `nodeAffinity`

* **`spec.affinity.nodeAffinity:`**
  * Configures node-based scheduling rules for the Pod.
* **`requiredDuringSchedulingIgnoredDuringExecution:`**
  * Enforces mandatory placement rules.
* **`nodeSelectorTerms:`**
  * A list of term blocks. If you provide **multiple** items under `nodeSelectorTerms` (multiple `- matchExpressions`), they are evaluated with **`OR`** logic (matching *any* term satisfies the rule).
* **`matchExpressions:`**
  * A list of label conditions inside a single term. Multiple items inside the same `matchExpressions` list are evaluated with **`AND`** logic (all conditions must match).
* **`operator:`**
  * **`In`**: Node's label value must be in the provided `values` list (supports `OR` across values, e.g., `Large` or `Medium`).
  * **`NotIn`**: Node's label value must not be in the `values` list (or the label key doesn't exist).
  * **`Exists`**: Node must have the specified label `key` (do not provide `values`).
  * **`DoesNotExist`**: Node must not have the specified label `key` (do not provide `values`).
  * **`Gt` / `Lt`**: Node's label value (parsed as an integer) must be greater than (`Gt`) or less than (`Lt`) the single string integer in `values` (e.g., `values: ["16"]`).
* **`preferredDuringSchedulingIgnoredDuringExecution:`**
  * Defines soft scoring preferences evaluated after hard rules pass.
* **`weight: 80`**
  * An integer between `1` and `100`. For every matching preferred rule, Kubernetes adds `weight` to that node's scheduling score and schedules the Pod on the node with the highest total score.

---

## Comparison: `nodeSelector` vs. `nodeAffinity`

| Feature | `nodeSelector` | `nodeAffinity` |
| :--- | :--- | :--- |
| **Syntax Complexity** | Very simple (`key: value`) | Verbose (`matchExpressions`) |
| **Operators Supported** | Exact equality (`=`) only | `In`, `NotIn`, `Exists`, `DoesNotExist`, `Gt`, `Lt` |
| **Soft Preferences?** | No (always hard requirement) | Yes (`preferredDuringScheduling...` with weights) |
| **`OR` Logic Support?** | No | Yes (multiple `values` in `In` or multiple `nodeSelectorTerms`) |

---

## Combining Taints/Tolerations + Node Affinity (Dedicated Nodes)

To guarantee that **only** your specific Pods run on a dedicated set of nodes—and that those Pods **never** land on general-purpose nodes—combine both features:

1. **Taint the dedicated node** (repels all other Pods):
   ```bash
   kubectl taint nodes gpu-node-01 dedicated=ml:NoSchedule
   ```
2. **Label the dedicated node** (attracts your ML Pods):
   ```bash
   kubectl label nodes gpu-node-01 dedicated=ml
   ```
3. **Add both `tolerations` and `nodeAffinity` to your Pod**:
   * `tolerations` permits the Pod to land on `gpu-node-01`.
   * `nodeAffinity` forces the Pod to choose `gpu-node-01` instead of other untainted nodes.