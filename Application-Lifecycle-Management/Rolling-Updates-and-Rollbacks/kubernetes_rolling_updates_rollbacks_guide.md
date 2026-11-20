# Kubernetes Rolling Updates and Rollbacks Guide

In Kubernetes, **Deployments** manage stateless application updates declaratively using **ReplicaSets**. Whenever you update a Deployment's Pod template (`spec.template`)—such as upgrading a container image, changing environment variables, or updating resource limits—Kubernetes triggers a new **Rollout** and creates a new revision.

## 1. Deployment Strategy Types (`spec.strategy.type`)

Kubernetes Deployments support **two** update strategies:

### Type 1: `RollingUpdate` *(Default — Zero Downtime)*

* **How it works:** Gradually replaces old Pods with new Pods one batch at a time. It scales up a new `ReplicaSet` while simultaneously scaling down the old `ReplicaSet`, ensuring the application remains online and serving traffic throughout the entire upgrade.
* **Best for:** Production web servers, microservices, and stateless APIs that require high availability.
* **Tuning Parameters (`spec.strategy.rollingUpdate`):**
  * **`maxUnavailable`**: The maximum number (or percentage, e.g., `25%`) of Pods that can be unavailable during the update process relative to `replicas`.
  * **`maxSurge`**: The maximum number (or percentage, e.g., `25%`) of extra Pods that can be created *above* the desired `replicas` count during the update.

> **Example Calculation (`replicas: 4`, `maxSurge: 25%`, `maxUnavailable: 25%`):**
> * Kubernetes can spin up $1$ extra Pod ($4 + 1 = 5$ total Pods) while terminating $1$ old Pod ($4 - 1 = 3$ minimum available Pods) at a time until all $4$ Pods run the new version.

### Type 2: `Recreate` *(All-at-Once — Brief Downtime)*

* **How it works:** Terminates **all** existing old Pods first, waits until every old Pod is completely shut down, and then creates all new Pods from scratch.
* **Best for:** Monolithic apps or workloads that cannot run two different application versions simultaneously (e.g., due to database schema locks or shared `ReadWriteOnce` storage volumes).

## 2. Complete Deployment Manifest with `RollingUpdate` Strategy

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
spec:
  replicas: 4
  revisionHistoryLimit: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
        - name: nginx-container
          image: nginx:1.26
          ports:
            - containerPort: 80
```

* **`revisionHistoryLimit: 10`** *(Default: `10`)*: Specifies how many old `ReplicaSets` Kubernetes retains so you can roll back to previous revisions. Setting it to `0` disables rollback history.

## 3. Essential Commands: Set Image, Status, History & Rollback

### A. Triggering an Update (`set image` or `apply`)

A new rollout is triggered **only** when fields inside `spec.template` change (like the container image). Scaling `replicas` does **not** create a new rollout revision.

```bash
# 1. Imperatively update the container image of a Deployment
# Syntax: kubectl set image deployment/<deployment-name> <container-name>=<new-image>
kubectl set image deployment/web-app nginx-container=nginx:1.27

# 2. Declaratively update via YAML file (Recommended for production)
kubectl apply -f deployment.yaml

# 3. Trigger a rolling restart without changing YAML or image (e.g., to reload ConfigMaps/Secrets)
kubectl rollout restart deployment/web-app
```

### B. Checking Rollout Status (`rollout status`)

```bash
# Watch the rollout progress live until all Pods are updated and Ready
kubectl rollout status deployment/web-app

# Watch the ReplicaSets transition in real time (old RS scales to 0, new RS scales to 4)
kubectl get rs -l app=web-app -w
```

### C. Viewing Revision History (`rollout history`)

```bash
# List all stored revisions of the Deployment
kubectl rollout history deployment/web-app

# Inspect the exact Pod template details (image, env, ports) of a specific revision
kubectl rollout history deployment/web-app --revision=2
```

> **Pro Tip (`kubernetes.io/change-cause`):** To make the `CHANGE-CAUSE` column in `kubectl rollout history` descriptive instead of `<none>`, annotate the Deployment right after updating:
> ```bash
> kubectl annotate deployment/web-app kubernetes.io/change-cause="Upgraded nginx to 1.27"
> ```

### D. Performing a Rollback (`rollout undo`)

If a new version introduces a bug or crashes (`CrashLoopBackOff`), roll back immediately:

```bash
# 1. Roll back to the immediately preceding revision
kubectl rollout undo deployment/web-app

# 2. Roll back to a SPECIFIC earlier revision number (e.g., revision 1)
kubectl rollout undo deployment/web-app --to-revision=1

# 3. Verify the rollback completed cleanly
kubectl rollout status deployment/web-app
```

### E. Pausing & Resuming a Rollout (`rollout pause` / `resume`)

Useful when you want to apply multiple changes (image + environment variables + resource limits) in a single rollout instead of triggering separate rollouts for each command:

```bash
# Pause rollouts on the Deployment
kubectl rollout pause deployment/web-app

# Apply multiple updates while paused
kubectl set image deployment/web-app nginx-container=nginx:1.28
kubectl set resources deployment/web-app -c=nginx-container --limits=cpu=500m,memory=256Mi

# Resume to roll out all queued changes together in one revision
kubectl rollout resume deployment/web-app
```

## 4. Quick Command Reference Summary

| Action | Command |
| :--- | :--- |
| **Update Image** | `kubectl set image deployment/<name> <container>=<image>` |
| **Check Rollout Status** | `kubectl rollout status deployment/<name>` |
| **View Revision History** | `kubectl rollout history deployment/<name>` |
| **Inspect Specific Revision** | `kubectl rollout history deployment/<name> --revision=<num>` |
| **Rollback to Previous** | `kubectl rollout undo deployment/<name>` |
| **Rollback to Specific Revision** | `kubectl rollout undo deployment/<name> --to-revision=<num>` |
| **Restart Pods Gracefully** | `kubectl rollout restart deployment/<name>` |
| **Pause / Resume Rollout** | `kubectl rollout pause` / `resume deployment/<name>` |