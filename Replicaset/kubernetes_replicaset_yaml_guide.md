# Kubernetes ReplicaSet YAML Manifest Guide

This document provides a standard `replicaset.yaml` manifest for running multiple replicas of an NGINX Pod and explains the purpose of every statement and field in the configuration.

## Complete `replicaset.yaml` Example

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx-replicaset
  namespace: default
  labels:
    app: nginx
    tier: frontend
spec:
  replicas: 3
  minReadySeconds: 5
  selector:
    matchLabels:
      app: nginx
      tier: frontend
  template:
    metadata:
      labels:
        app: nginx
        tier: frontend
    spec:
      containers:
        - name: nginx-container
          image: nginx:1.27
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          resources:
            requests:
              memory: "64Mi"
              cpu: "250m"
            limits:
              memory: "128Mi"
              cpu: "500m"
```

## Statement-by-Statement Explanation

### 1. Top-Level Fields

* **`apiVersion: apps/v1`**
  * **What it does:** Specifies the Kubernetes API group (`apps`) and version (`v1`) required for workload controllers.
  * **Why it matters:** Unlike standalone `Pod` objects (which use `v1`), controllers such as `ReplicaSet`, `Deployment`, `DaemonSet`, and `StatefulSet` belong to the `apps/v1` API group.
* **`kind: ReplicaSet`**
  * **What it does:** Declares that this manifest defines a **ReplicaSet** resource.
  * **Why it matters:** A ReplicaSet's sole responsibility is to ensure a specified number of identical Pod replicas are running at any given time—automatically creating new Pods if one crashes or a node goes down, and terminating excess Pods if too many exist.

### 2. `metadata` Section (ReplicaSet Identification)

* **`metadata:`**
  * **What it does:** Holds identifying information for the ReplicaSet controller object itself.
* **`name: nginx-replicaset`**
  * **What it does:** Assigns a unique name to the ReplicaSet within its namespace.
  * **Why it matters:** Pods created by this ReplicaSet will automatically inherit this name as a prefix followed by a random 5-character hash (e.g., `nginx-replicaset-a1b2c`).
* **`namespace: default`**
  * **What it does:** Places the ReplicaSet (and all Pods it manages) into the `default` namespace.
* **`labels:`**
  * **What it does:** Attaches metadata tags (`app: nginx`, `tier: frontend`) to the ReplicaSet object itself so you can filter or query ReplicaSets using `kubectl get rs -l app=nginx`.

### 3. `spec` Section (ReplicaSet Behavior)

* **`spec:`**
  * **What it does:** Defines the desired state for the ReplicaSet controller.
* **`replicas: 3`**
  * **What it does:** Sets the desired number of identical Pods that should be running simultaneously.
  * **Why it matters:** If a Pod is deleted or fails, the ReplicaSet controller detects that the current count ($2$) is less than the desired count ($3$) and immediately schedules a replacement Pod.
* **`minReadySeconds: 5`** *(Optional)*
  * **What it does:** Specifies the minimum number of seconds a newly created Pod must run without any container crashes before the ReplicaSet considers it "available."
  * **Why it matters:** Helps prevent premature traffic routing or cascading failures when containers start up and crash shortly afterward.

### 4. `selector` Section (Pod Ownership & Tracking)

* **`selector:`**
  * **What it does:** Defines how the ReplicaSet identifies which Pods in the cluster belong to it.
  * **Why it matters:** This is a **required** field in `apps/v1`. The ReplicaSet continuously counts all active Pods in the same namespace whose labels match this selector.
* **`matchLabels:`**
  * **What it does:** Requires Pods to possess **all** listed key-value pairs (`app: nginx` AND `tier: frontend`) to be managed by this ReplicaSet.
  * **Critical Rule:** The labels under `spec.selector.matchLabels` **must** match the labels defined inside `spec.template.metadata.labels`. If they do not match, the Kubernetes API server will reject the manifest with a validation error.

### 5. `template` Section (The Pod Blueprint)

* **`template:`**
  * **What it does:** Acts as an embedded `Pod` manifest blueprint. Whenever the ReplicaSet needs to scale up or replace a failed Pod, it stamps out a new Pod using this exact template.
* **`template.metadata.labels:`**
  * **What it does:** Applies `app: nginx` and `tier: frontend` to every Pod spawned from this template so that the ReplicaSet's `selector` immediately recognizes and adopts them.
  * *(Note: `template.metadata.name` is intentionally omitted because Kubernetes automatically generates unique names for each replica).*
* **`template.spec:`**
  * **What it does:** Contains the standard Pod specification (`containers`, `image`, `ports`, `resources`, etc.), identical to the `spec` section of a standalone `pod.yaml`.

## ReplicaSet vs. Deployment: Quick Note

While a **ReplicaSet** guarantees that a specific number of Pods stay running, you rarely create standalone ReplicaSets directly in production. Instead, you create a **Deployment**, which automatically creates and manages ReplicaSets behind the scenes to enable **rolling updates** and **rollbacks** when you change container versions.

## Quick Usage Commands

```bash
# Create the ReplicaSet
kubectl apply -f replicaset.yaml

# View the ReplicaSet status (DESIRED, CURRENT, READY)
kubectl get replicaset nginx-replicaset

# Watch the 3 managed Pods being created
kubectl get pods -l app=nginx -o wide

# Test self-healing by deleting one Pod and watching a replacement spawn
kubectl delete pod <pod-name>
kubectl get pods -l app=nginx

# Scale the ReplicaSet manually to 5 replicas
kubectl scale replicaset nginx-replicaset --replicas=5

# Delete the ReplicaSet and all its managed Pods
kubectl delete -f replicaset.yaml
```