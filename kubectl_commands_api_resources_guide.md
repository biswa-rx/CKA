# Essential `kubectl` Commands & `api-resources` Reference Guide

This guide covers the most frequently used `kubectl` commands for daily cluster administration, debugging, and deployment management, along with a complete explanation of how to discover resource types, shortnames, and API versions using `kubectl api-resources`.

---

## Part 1: Understanding `kubectl api-resources`

Every object in Kubernetes (Pods, Deployments, Services, Nodes) is exposed through the Kubernetes REST API. The `kubectl api-resources` command queries the API server and lists every resource type supported by your cluster, its shortname, its API group/version, and whether it is namespaced.

### Basic Command
```bash
kubectl api-resources
```

### Example Output & Column Breakdown

```text
NAME               SHORTNAMES   APIVERSION        NAMESPACED   KIND
namespaces         ns           v1                false        Namespace
nodes              no           v1                false        Node
pods               po           v1                true         Pod
services           svc          v1                true         Service
configmaps         cm           v1                true         ConfigMap
secrets                         v1                true         Secret
deployments        deploy       apps/v1           true         Deployment
replicasets        rs           apps/v1           true         ReplicaSet
daemonsets         ds           apps/v1           true         DaemonSet
statefulsets       sts          apps/v1           true         StatefulSet
ingresses          ing          networking.k8s.io/v1 true     Ingress
```

* **`NAME`**: The plural resource name used in `kubectl` commands (e.g., `kubectl get pods`).
* **`SHORTNAMES`**: Official abbreviations you can use to type commands faster (e.g., `kubectl get po,svc,deploy` instead of `kubectl get pods,services,deployments`).
* **`APIVERSION`**: The exact string you must put in the `apiVersion:` field of your YAML manifests (e.g., `v1` for Pods/Services, `apps/v1` for Deployments/ReplicaSets).
* **`NAMESPACED`**:
  * `true`: The resource lives inside a namespace (`-n <namespace>`).
  * `false`: The resource is cluster-scoped (global across the entire cluster, like `Node` or `Namespace`).
* **`KIND`**: The exact PascalCase name you must put in the `kind:` field of your YAML manifests.

### Useful `kubectl api-resources` Filter Flags

```bash
# List only namespaced resources
kubectl api-resources --namespaced=true

# List only cluster-scoped (global) resources
kubectl api-resources --namespaced=false

# Filter resources belonging to a specific API group (e.g., apps or networking.k8s.io)
kubectl api-resources --api-group=apps

# List resources that support a specific verb (e.g., list, delete, watch)
kubectl api-resources --verbs=list,get

# View all supported API versions in your cluster
kubectl api-versions
```

---

## Part 2: Most Used `kubectl` Commands

### 1. Cluster & Node Inspection
Commands for checking cluster health, context, and node capacity.

```bash
# Display cluster control-plane and CoreDNS endpoints
kubectl cluster-info

# List all nodes with status, roles, Kubernetes version, and internal/external IPs
kubectl get nodes -o wide

# Show detailed hardware specs, labels, taints, and conditions of a node
kubectl describe node <node-name>

# View real-time CPU and memory usage per node (requires Metrics Server)
kubectl top nodes
```

### 2. Viewing & Listing Resources (`get`)
Commands for inspecting objects in your cluster.

```bash
# List Pods in the current namespace
kubectl get pods   # or: kubectl get po

# List Pods with node placement, IP address, and readiness details
kubectl get po -o wide

# List Pods across ALL namespaces
kubectl get po -A

# List multiple resource types at once using shortnames
kubectl get po,svc,deploy,rs

# Watch resources update live in real time (Ctrl+C to exit)
kubectl get po -w

# Filter resources by label
kubectl get po -l app=nginx

# Output the full live YAML or JSON definition of a running resource
kubectl get pod <pod-name> -o yaml
kubectl get svc nginx-service -o json
```

### 3. Creating & Updating Resources (`apply` & `create`)
Commands for deploying manifests or generating YAML templates quickly.

```bash
# Create or update resources declaratively from a YAML file (Recommended)
kubectl apply -f deployment.yaml

# Apply all YAML files inside a directory
kubectl apply -f ./manifests/

# Generate a clean YAML template without creating the resource (--dry-run=client)
kubectl create deployment nginx --image=nginx:1.27 --replicas=3 --dry-run=client -o yaml > deploy.yaml
kubectl run test-pod --image=nginx --dry-run=client -o yaml > pod.yaml
```
> **Pro Tip:** Combining `--dry-run=client -o yaml` is the fastest way to generate valid YAML skeletons without memorizing indentation!

### 4. Troubleshooting & Debugging (`describe`, `logs`, `exec`)
The most important commands when a Pod is stuck in `Pending`, `CrashLoopBackOff`, or `ImagePullBackOff`.

```bash
# Inspect detailed configuration and recent lifecycle Events (crucial for errors)
kubectl describe pod <pod-name>

# View standard output logs of a Pod
kubectl logs <pod-name>

# Stream logs live (-f = follow)
kubectl logs -f <pod-name>

# View logs of a specific container inside a multi-container Pod
kubectl logs <pod-name> -c <container-name>

# View logs from a previous crashed instance of a container
kubectl logs <pod-name> --previous

# Open an interactive shell inside a running container
kubectl exec -it <pod-name> -- /bin/bash
# (Use /bin/sh for lightweight Alpine/BusyBox images)
kubectl exec -it <pod-name> -- /bin/sh

# View real-time CPU and memory usage per Pod (requires Metrics Server)
kubectl top pods

# View cluster-wide events sorted chronologically
kubectl get events --sort-by='.metadata.creationTimestamp'
```

### 5. Scaling & Rollout Management (`scale`, `rollout`)
Commands for managing Deployments and zero-downtime updates.

```bash
# Scale a Deployment up or down immediately
kubectl scale deployment nginx-deployment --replicas=5

# Update the container image of a Deployment (triggers a RollingUpdate)
kubectl set image deployment/nginx-deployment nginx-container=nginx:1.28

# Watch the rollout status until completion
kubectl rollout status deployment/nginx-deployment

# View revision history of a Deployment
kubectl rollout history deployment/nginx-deployment

# Roll back to the previous working version
kubectl rollout undo deployment/nginx-deployment

# Restart all Pods in a Deployment gracefully without changing YAML
kubectl rollout restart deployment/nginx-deployment
```

### 6. Port Forwarding & Quick Testing (`port-forward`, `run`)
Commands for testing services locally or running temporary network debugging tools.

```bash
# Forward local machine port 8080 to port 80 of a Pod or Service
kubectl port-forward pod/<pod-name> 8080:80
kubectl port-forward svc/nginx-service 8080:80

# Spin up a temporary interactive Pod for DNS/network testing and auto-delete on exit (--rm)
kubectl run tmp-debug --rm -it --image=busybox -- /bin/sh
```

### 7. Deleting & Cleaning Up Resources (`delete`)

```bash
# Delete resources defined in a YAML file
kubectl delete -f deployment.yaml

# Delete a specific resource by type and name
kubectl delete pod <pod-name>
kubectl delete svc nginx-service

# Force delete a stuck Pod immediately
kubectl delete pod <pod-name> --grace-period=0 --force
```

---

## Quick Shortnames Cheat Sheet

| Full Resource Name | Shortname | API Version | Scope |
| :--- | :--- | :--- | :--- |
| `pods` | `po` | `v1` | Namespaced |
| `services` | `svc` | `v1` | Namespaced |
| `namespaces` | `ns` | `v1` | Cluster |
| `nodes` | `no` | `v1` | Cluster |
| `configmaps` | `cm` | `v1` | Namespaced |
| `persistentvolumes` | `pv` | `v1` | Cluster |
| `persistentvolumeclaims` | `pvc` | `v1` | Namespaced |
| `deployments` | `deploy` | `apps/v1` | Namespaced |
| `replicasets` | `rs` | `apps/v1` | Namespaced |
| `daemonsets` | `ds` | `apps/v1` | Namespaced |
| `statefulsets` | `sts` | `apps/v1` | Namespaced |
| `ingresses` | `ing` | `networking.k8s.io/v1` | Namespaced |