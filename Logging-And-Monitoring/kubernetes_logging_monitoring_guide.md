# Kubernetes Logging & Monitoring Guide

Observability in Kubernetes relies on two complementary pillars:
1. **Monitoring (Metrics):** Tracking CPU, memory, disk, and network utilization across nodes, control-plane components, and Pods over time.
2. **Logging:** Capturing standard output/error streams and system logs from containers, nodes, and control-plane services for troubleshooting and auditing.

---

## Part 1: Monitoring Cluster Components

Kubernetes does **not** ship with a built-in long-term metrics database out of the box. Instead, monitoring happens in two layers:
* **In-Memory Resource Metrics Pipeline (`metrics-server`):** Collects real-time CPU and memory metrics for `kubectl top` and autoscaling (`HorizontalPodAutoscaler` / `VerticalPodAutoscaler`).
* **Full Monitoring Stack (Prometheus + Grafana):** Scrapes detailed time-series metrics from nodes, kubelets, control-plane components, and applications for dashboards and alerting.

### 1. How `metrics-server` Works

```
[kubelet + cAdvisor on each Node]
              │
              ▼  (Scrapes CPU & Memory every 15s via Summary API)
       [metrics-server]  (In-memory only, no disk storage)
              │
              ▼  (Exposes metrics.k8s.io API)
   kubectl top nodes / pods  &  HPA (Autoscaler)
```

* **`cAdvisor` (Container Advisor):** Built directly into every node's `kubelet` daemon; collects real-time container CPU, memory, filesystem, and network stats.
* **`metrics-server`:** A lightweight Deployment running in `kube-system` that aggregates metrics from every `kubelet` and exposes them via the `metrics.k8s.io` API group.

### 2. Installing `metrics-server` on a `kubeadm` Cluster

On `kubeadm` clusters (where `kubelet` uses self-signed serving certificates by default), you must pass `--kubelet-insecure-tls` to `metrics-server`:

```bash
# 1. Download the official Metrics Server manifest
wget https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 2. Add '--kubelet-insecure-tls' under spec.template.spec.containers[0].args in components.yaml
# (Required on kubeadm labs using self-signed kubelet certificates)

# 3. Apply the manifest
kubectl apply -f components.yaml

# 4. Verify metrics-server is Running and Ready
kubectl get pods -n kube-system -l k8s-app=metrics-server
```

### 3. Essential `kubectl top` & Cluster Health Commands

```bash
# View real-time CPU (cores/millicores) and Memory (Mi/Gi) usage per Node
kubectl top nodes

# View real-time CPU and Memory usage per Pod in the current namespace
kubectl top pods

# View Pod resource usage across ALL namespaces, sorted by CPU or Memory
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# View individual container resource usage inside multi-container Pods
kubectl top pods --containers

# Check control-plane static Pods and system DaemonSets health
kubectl get pods -n kube-system -o wide

# Check node health conditions (Ready, MemoryPressure, DiskPressure, PIDPressure)
kubectl get nodes
kubectl describe node <node-name> | grep -A 6 "Conditions:"
```

### 4. Monitoring Control-Plane Components (Prometheus Architecture)

For production dashboards and historical alerting, **Prometheus** scrapes `/metrics` endpoints exposed by core cluster components:
* **`kube-apiserver`** (`:6443/metrics`): Request latency, HTTP error rates, `etcd` latency.
* **`kube-scheduler`** (`:10259/metrics`): Scheduling queue depth, scheduling latency, preemption counts.
* **`kube-controller-manager`** (`:10257/metrics`): Reconciliation loop queue depths and work durations.
* **`etcd`** (`:2381/metrics`): Database size, leader elections, fsync disk latency.
* **`kubelet` & `node-exporter`** (`:10250/metrics`, `:9100/metrics`): Host-level CPU, RAM, disk I/O, and network packet drops.
* **`kube-state-metrics`**: Translates Kubernetes API object states (e.g., `Deployment` desired vs. available replicas, `CrashLoopBackOff` counts) into Prometheus metrics.

---

## Part 2: Managing Application Logs

In Kubernetes, containerized applications are designed to write logs directly to **`stdout`** (standard output) and **`stderr`** (standard error) rather than writing to log files inside the container filesystem.

### 1. Where Container Logs Live on the Node

When a container writes to `stdout`/`stderr`, the container runtime (`containerd` or `CRI-O`) intercepts the stream and writes JSON-formatted log lines to disk on the host node:

* **Container Log Symlinks:** `/var/log/containers/<pod-name>_<namespace>_<container-name>-<id>.log`
* **Pod Log Directories:** `/var/log/pods/<namespace>_<pod-name>_<uid>/<container-name>/0.log`
* **Log Rotation:** Handled automatically by `kubelet` (`containerLogMaxSize`, default `10Mi`, and `containerLogMaxFiles`, default `5`), preventing container logs from filling up the node's root disk.

> **Important Ephemeral Warning:** If a Pod is deleted or evicted from a node, `kubelet` garbage-collects its local log files on that node. Production clusters therefore ship logs off nodes to a centralized backend (Elasticsearch/OpenSearch, Grafana Loki, Splunk, or CloudWatch).

### 2. Essential `kubectl logs` Commands

```bash
# View logs from a single-container Pod
kubectl logs <pod-name>

# Stream logs in real time (-f = follow)
kubectl logs -f <pod-name>

# View logs of a specific container inside a multi-container Pod (-c)
kubectl logs <pod-name> -c <container-name>

# View logs from ALL containers in a Pod simultaneously
kubectl logs <pod-name> --all-containers=true

# View logs from the PREVIOUS crashed instance of a container (essential for CrashLoopBackOff!)
kubectl logs <pod-name> --previous   # or: -p

# Show only the last 50 lines of logs
kubectl logs <pod-name> --tail=50

# Show logs from the last 15 minutes with timestamps
kubectl logs <pod-name> --since=15m --timestamps

# Stream logs from all Pods matching a label selector (e.g., all replicas in a Deployment)
kubectl logs -l app=nginx --tail=20 -f
```

### 3. Inspecting Control-Plane & Node System Logs

When `kubectl logs` isn't available (for instance, if `kube-apiserver` is down), inspect logs directly on the node:

```bash
# View systemd service logs for kubelet and containerd on the host
sudo journalctl -u kubelet -n 100 --no-pager
sudo journalctl -u containerd -n 100 --no-pager

# Read static control-plane Pod logs directly from /var/log/containers/
sudo tail -n 50 /var/log/containers/kube-apiserver-*.log
sudo tail -n 50 /var/log/containers/kube-scheduler-*.log
```

---

## Part 3: Cluster-Level Logging Architectures

Because Kubernetes does not provide a native centralized log storage solution, production clusters use one of three standard patterns:

### Pattern 1: Node-Level Logging Agent (`DaemonSet`) — *Recommended Standard*

```
[App Pod] ──(stdout/stderr)──► [/var/log/containers/*.log on Node]
                                            ▲
                                            │ (Reads & ships logs)
                              [Fluent Bit / Promtail DaemonSet Pod]
                                            │
                                            ▼
                             [Central Storage: Loki / Elasticsearch]
```

* **How it works:** A logging agent (such as **Fluent Bit**, **Fluentd**, **Promtail**, or **Vector**) runs as a **DaemonSet** on every node, mounts `/var/log/containers` as a read-only `hostPath` volume, enriches logs with Kubernetes metadata (Pod name, namespace, labels), and forwards them to centralized storage.
* **Pros:** Lowest resource overhead (only 1 agent Pod per node); requires zero changes to application Pods.

### Pattern 2: Sidecar Streaming Container (For Legacy File-Based Apps)

If a legacy application writes logs to a local file inside the container (e.g., `/var/log/app/access.log`) instead of `stdout`, attach a lightweight **streaming sidecar container** sharing an `emptyDir` volume that tails the file to `stdout` so `kubectl logs` and node-level DaemonSets can capture it:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: legacy-web-app
spec:
  containers:
    # Main legacy container writing logs to a file
    - name: legacy-app
      image: busybox:1.36
      command: ["/bin/sh", "-c"]
      args:
        - while true; do echo "$(date) INFO Request processed" >> /var/log/app/app.log; sleep 5; done
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/app

    # Sidecar container streaming the log file to stdout
    - name: log-streamer-sidecar
      image: busybox:1.36
      command: ["/bin/sh", "-c", "tail -n+1 -F /var/log/app/app.log"]
      volumeMounts:
        - name: shared-logs
          mountPath: /var/log/app
  volumes:
    - name: shared-logs
      emptyDir: {}
```

* To view the streamed logs: `kubectl logs legacy-web-app -c log-streamer-sidecar`

### Pattern 3: Direct Application Push

* The application itself uses a logging SDK/library to push logs directly over the network to a backend (e.g., Datadog, Splunk, or Elasticsearch) without involving `kubelet` or node log files.

---

## Quick Troubleshooting Cheat Sheet

| Symptom | First Command to Run | What to Look For |
| :--- | :--- | :--- |
| **`kubectl top` returns `Metrics API not available`** | `kubectl get pods -n kube-system -l k8s-app=metrics-server` | Verify `metrics-server` is installed and `Ready` (check `--kubelet-insecure-tls` on `kubeadm`). |
| **Pod stuck in `CrashLoopBackOff`** | `kubectl logs <pod-name> --previous` | Stack trace or configuration error from the container right before it exited. |
| **Pod terminated with `OOMKilled` (Exit Code 137)** | `kubectl describe pod <pod-name>` & `kubectl top pod` | Container exceeded its `resources.limits.memory`; increase memory limit or fix memory leak. |
| **Multi-container Pod error** | `kubectl logs <pod-name> --all-containers=true` | Identify whether the main container or an init/sidecar container failed. |