# Kubernetes Deployment YAML Manifest Guide

This document provides a production-ready `deployment.yaml` manifest for an NGINX application and explains the purpose of every statement and field, including rollout strategies and revision history.

## Complete `deployment.yaml` Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
  labels:
    app: nginx
    tier: frontend
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
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
  * **What it does:** Specifies the Kubernetes API group (`apps`) and version (`v1`) for workload controllers.
  * **Why it matters:** Like `ReplicaSet`, `Deployment` belongs to the stable `apps/v1` API group.
* **`kind: Deployment`**
  * **What it does:** Declares that this manifest defines a **Deployment** resource.
  * **Why it matters:** A Deployment provides declarative updates for Pods and ReplicaSets. Rather than managing ReplicaSets manually, you describe the desired state in a Deployment, and the Deployment Controller changes the actual state to the desired state at a controlled rate (supporting zero-downtime rolling updates and instant rollbacks).

### 2. `metadata` Section (Deployment Identification)

* **`metadata:`**
  * **What it does:** Contains metadata that uniquely identifies the Deployment object.
* **`name: nginx-deployment`**
  * **What it does:** Assigns a unique name to the Deployment within its namespace.
  * **Naming Hierarchy:** A Deployment named `nginx-deployment` creates a ReplicaSet named `nginx-deployment-<pod-template-hash>` (e.g., `nginx-deployment-7fb96c846b`), which in turn creates Pods named `nginx-deployment-7fb96c846b-<random-id>`.
* **`namespace: default`**
  * **What it does:** Places the Deployment, its ReplicaSets, and its Pods into the `default` namespace.
* **`labels:`**
  * **What it does:** Attaches identifying key-value pairs (`app: nginx`, `tier: frontend`) to the Deployment object itself.

### 3. `spec` Section (Deployment Behavior & Rollout Control)

* **`spec:`**
  * **What it does:** Defines the desired state, scaling count, and update behavior for the Deployment.
* **`replicas: 3`**
  * **What it does:** Instructs the underlying ReplicaSet to maintain $3$ identical running Pods at all times.
* **`revisionHistoryLimit: 5`** *(Optional)*
  * **What it does:** Specifies how many old ReplicaSets to retain in the cluster so you can roll back to previous versions if an update breaks your application.
  * **Why it matters:** By default, Kubernetes keeps $10$ old ReplicaSets. Setting this to `5` keeps `kubectl get rs` cleaner while still preserving your last $5$ deployment revisions.

### 4. `strategy` Section (How Updates Happen)

* **`strategy:`**
  * **What it does:** Defines the mechanism used to replace old Pods with new ones when you modify `spec.template` (for example, updating `image: nginx:1.27` to `nginx:1.28`).
* **`type: RollingUpdate`**
  * **What it does:** Gradually replaces old Pods with new ones without taking the application offline.
  * **Alternative (`Recreate`):** Terminates all existing Pods *before* creating new ones (causes brief downtime, useful when two versions cannot run simultaneously).
* **`rollingUpdate:`**
  * **What it does:** Fine-tunes the speed and safety of a `RollingUpdate`.
* **`maxUnavailable: 1`**
  * **What it does:** Sets the maximum number (or percentage, e.g., `25%`) of Pods that can be unavailable during an update. With `replicas: 3` and `maxUnavailable: 1`, at least $2$ Pods are guaranteed to stay online serving traffic throughout the update.
* **`maxSurge: 1`**
  * **What it does:** Sets the maximum number (or percentage) of extra Pods that can be created *above* the desired `replicas` count during an update. With `replicas: 3` and `maxSurge: 1`, Kubernetes can temporarily run up to $4$ total Pods while spinning up new versions before terminating old ones.

### 5. `selector` Section (Pod Tracking)

* **`selector:`**
  * **What it does:** Tells the Deployment which Pods it manages.
* **`matchLabels:`**
  * **What it does:** Matches Pods that have both `app: nginx` and `tier: frontend`.
  * **Critical Rule:** In `apps/v1`, `spec.selector` is **immutable** (cannot be changed after creation) and **must** match `spec.template.metadata.labels`.

### 6. `template` Section (The Pod Blueprint)

* **`template:`**
  * **What it does:** Defines the Pod specification stamped out by the Deployment's active ReplicaSet.
  * **How updates trigger:** Any change inside `spec.template` (such as changing the container `image`, environment variables, or resource limits) triggers a brand-new rollout, creating a new ReplicaSet and gradually scaling down the old ReplicaSet.
* **`template.metadata.labels:`**
  * **What it does:** Stamps `app: nginx` and `tier: frontend` onto every created Pod so both the Deployment and any matching `Service` can route traffic to them.
* **`template.spec:`**
  * **What it does:** Defines the container runtime details (`containers`, `image`, `ports`, and `resources`), identical to the `spec` inside a `Pod` or `ReplicaSet`.

## Quick Usage & Rollout Commands

```bash
# Create or update the Deployment
kubectl apply -f deployment.yaml

# Check Deployment status (READY, UP-TO-DATE, AVAILABLE)
kubectl get deployment nginx-deployment

# Watch a live rolling update in progress
kubectl rollout status deployment/nginx-deployment

# Update the NGINX image imperatively (triggers a RollingUpdate)
kubectl set image deployment/nginx-deployment nginx-container=nginx:1.28

# View rollout revision history
kubectl rollout history deployment/nginx-deployment

# Roll back to the previous revision if something goes wrong
kubectl rollout undo deployment/nginx-deployment

# Scale the Deployment to 5 replicas
kubectl scale deployment nginx-deployment --replicas=5

# Delete the Deployment, its ReplicaSets, and its Pods
kubectl delete -f deployment.yaml
```