# Kubernetes Pod YAML Manifest Guide

This document provides a standard `pod.yaml` manifest for an NGINX container and explains the purpose of every statement and field in the configuration.

## Complete `pod.yaml` Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  namespace: default
  labels:
    app: nginx
    environment: dev
spec:
  restartPolicy: Always
  containers:
    - name: nginx-container
      image: nginx:1.27
      imagePullPolicy: IfNotPresent
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

---

## Statement-by-Statement Explanation

### 1. Top-Level Fields (Required in Every Kubernetes Manifest)

* **`apiVersion: v1`**
  * **What it does:** Specifies which version of the Kubernetes API you are using to create this object.
  * **Why it matters:** Core Kubernetes resources like `Pod`, `Service`, `Namespace`, and `Node` belong to the legacy core API group, represented simply as `v1`.

* **`kind: Pod`**
  * **What it does:** Declares the type of Kubernetes resource you want to create.
  * **Why it matters:** Tells the Kubernetes API server to validate and schedule this manifest as a **Pod** (the smallest deployable unit in Kubernetes, which wraps one or more containers).

---

### 2. `metadata` Section (Object Identification)

* **`metadata:`**
  * **What it does:** Contains data that helps uniquely identify the Pod within the cluster.

* **`name: nginx-pod`**
  * **What it does:** Assigns a unique string name (`nginx-pod`) to the Pod.
  * **Why it matters:** No two Pods in the same namespace can share the exact same `name`. You use this name when running commands like `kubectl describe pod nginx-pod` or `kubectl logs nginx-pod`.

* **`namespace: default`**
  * **What it does:** Specifies the virtual cluster partition (namespace) where the Pod will live.
  * **Why it matters:** Helps organize resources across teams or environments. If omitted, Kubernetes automatically places the Pod into the `default` namespace.

* **`labels:`**
  * **What it does:** Attaches arbitrary key-value pairs (`app: nginx`, `environment: dev`) to the Pod.
  * **Why it matters:** Labels do not directly change how the Pod runs, but they are critical for **Services**, **Deployments**, and `kubectl` queries (`kubectl get pods -l app=nginx`) to find and group matching Pods.

---

### 3. `spec` Section (Desired State)

* **`spec:`**
  * **What it does:** Defines the *desired state* of the Pod—what containers should run inside it and how Kubernetes should manage them.

* **`restartPolicy: Always`**
  * **What it does:** Instructs the `kubelet` on the worker node on what to do if a container inside the Pod exits or crashes.
  * **Options:**
    * `Always` (default): Always restarts the container regardless of exit code.
    * `OnFailure`: Restarts only if the container exits with a non-zero error code.
    * `Never`: Never restarts the container (commonly used for one-off batch jobs).

---

### 4. `containers` Section (Container Configuration)

* **`containers:`**
  * **What it does:** Begins a YAML list (indicated by `-`) of one or more containers that will run inside this Pod. All containers in a Pod share the same IP address, network ports, and local storage volumes.

* **`- name: nginx-container`**
  * **What it does:** Assigns a local name to this specific container inside the Pod.
  * **Why it matters:** Required if a Pod runs multiple containers (e.g., an app container + a logging sidecar) so you can inspect logs for a specific container via `kubectl logs nginx-pod -c nginx-container`.

* **`image: nginx:1.27`**
  * **What it does:** Specifies the container image and tag (`1.27`) that the container runtime (`containerd`) will download from Docker Hub (or another configured registry).
  * **Best Practice:** Always pin a specific version tag rather than `:latest` to ensure predictable deployments.

* **`imagePullPolicy: IfNotPresent`**
  * **What it does:** Controls when `containerd` pulls the image from the container registry.
  * **Options:**
    * `IfNotPresent`: Pulls the image only if it is not already cached locally on the node.
    * `Always`: Always checks the registry for a newer image digest before starting.
    * `Never`: Only uses local images and never attempts to pull from a registry.

---

### 5. `ports` Section (Container Networking)

* **`ports:`**
  * **What it does:** Lists the network ports exposed by the container process.

* **`- name: http`**
  * **What it does:** Gives the port a descriptive name (`http`) that can be referenced by name in a Kubernetes `Service` definition.

* **`containerPort: 80`**
  * **What it does:** Documents that the NGINX process inside the container listens on port `80`.
  * **Why it matters:** Primarily informational for humans and Services; any container inside the same Pod can already reach port `80` over `localhost`.

* **`protocol: TCP`**
  * **What it does:** Explicitly sets the network transport protocol (`TCP` is the default; `UDP` and `SCTP` are also supported).

---

### 6. `resources` Section (CPU & Memory Management)

* **`resources:`**
  * **What it does:** Defines compute resource guarantees and boundaries for the container.

* **`requests:`**
  * **What it does:** The minimum amount of CPU (`250m` = $0.25$ of a CPU core, or $250\text{ millicores}$) and memory (`64Mi` = $64\text{ Mebibytes}$) guaranteed to this container.
  * **Why it matters:** The Kubernetes Scheduler uses `requests` to decide which worker node has enough free capacity to host the Pod.

* **`limits:`**
  * **What it does:** The maximum amount of CPU (`500m` = $0.5$ CPU core) and memory (`128Mi`) the container is allowed to consume.
  * **Why it matters:** If the container tries to exceed its CPU limit, Kubernetes throttles it. If it exceeds its memory limit, the kernel terminates the container with an `OOMKilled` (Out Of Memory) error to protect the node.

---

## Quick Usage Commands

```bash
# Create the Pod from the YAML file
kubectl apply -f pod.yaml

# Check Pod status and IP address
kubectl get pod nginx-pod -o wide

# View detailed events and configuration
kubectl describe pod nginx-pod

# Delete the Pod
kubectl delete -f pod.yaml
```