# Kubernetes Service YAML Manifest & Types Guide

In Kubernetes, Pods are ephemeral—they get created, destroyed, and assigned new internal IP addresses dynamically. A **Service** provides a stable virtual IP address, DNS name, and load-balancing layer to route traffic reliably to a dynamic set of Pods.

## Complete `service.yaml` Example (`NodePort`)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: default
  labels:
    app: nginx
    tier: frontend
spec:
  type: NodePort
  selector:
    app: nginx
    tier: frontend
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080
```

---

## Statement-by-Statement Explanation

### 1. Top-Level Fields

* **`apiVersion: v1`**
  * **What it does:** Specifies that `Service` belongs to the core Kubernetes `v1` API group.
* **`kind: Service`**
  * **What it does:** Declares that this manifest defines a **Service** networking resource.

### 2. `metadata` Section (Service Identification)

* **`metadata:`**
  * **What it does:** Identifies the Service object inside the cluster.
* **`name: nginx-service`**
  * **What it does:** Assigns a unique name to the Service.
  * **Built-in DNS:** CoreDNS automatically creates an internal DNS record for this Service (`nginx-service.default.svc.cluster.local`), allowing other Pods in the same namespace to reach it simply by calling `http://nginx-service`.
* **`namespace: default`**
  * **What it does:** Places the Service in the `default` namespace. *(Note: A Service can only route traffic to Pods located in the same namespace).*
* **`labels:`**
  * **What it does:** Attaches metadata tags (`app: nginx`, `tier: frontend`) to the Service object itself.

### 3. `spec` Section (Routing & Port Mapping)

* **`spec:`**
  * **What it does:** Defines how the Service exposes Pods and forwards network traffic.
* **`type: NodePort`**
  * **What it does:** Determines how the Service is exposed internally or externally (explained in detail in the next section). If omitted, Kubernetes defaults to `ClusterIP`.
* **`selector:`**
  * **What it does:** Tells the Service which Pods should receive traffic.
  * **How it works:** The Service continuously watches for any active, ready Pods that carry **both** `app: nginx` and `tier: frontend` labels, automatically adding their IP addresses to an internal `Endpoints` / `EndpointSlice` list and load-balancing requests across them.
* **`ports:`**
  * **What it does:** Defines a list of port mappings for incoming and outgoing traffic.
* **`- name: http`**
  * **What it does:** Names the port mapping (`http`). Required if a Service exposes more than one port (e.g., port `80` for HTTP and port `443` for HTTPS).
* **`protocol: TCP`**
  * **What it does:** Sets the transport protocol (`TCP` is default; `UDP` and `SCTP` are also supported).
* **`port: 80`**
  * **What it does:** The port exposed internally on the Service's virtual `ClusterIP`. Other Pods inside the cluster send traffic to `<ClusterIP>:80`.
* **`targetPort: 80`**
  * **What it does:** The actual port (`containerPort`) that the application inside the Pod is listening on. Traffic arriving at `port: 80` on the Service is forwarded to `targetPort: 80` on the backend Pods. *(If omitted, it defaults to the same value as `port`).*
* **`nodePort: 30080`** *(Only valid for `NodePort` and `LoadBalancer` types)*
  * **What it does:** Opens static port `30080` on every worker and control-plane node's IP address so external clients can access the app via `http://<Node-IP>:30080`.
  * **Valid Range:** Must be between `30000` and `32767`. If omitted, Kubernetes automatically assigns an available random port in that range.

---

## Types of Kubernetes Services

Kubernetes offers four primary Service types depending on whether traffic originates inside or outside the cluster:

### 1. `ClusterIP` (Default)
* **How it works:** Exposes the Service on an internal-only virtual IP address (`ClusterIP`) reachable *only* from within the Kubernetes cluster.
* **Use Case:** Internal microservices communication—such as backend APIs, databases (PostgreSQL, Redis), or internal caches that should never be directly accessible from the public internet.

### 2. `NodePort`
* **How it works:** Builds on top of `ClusterIP` by opening a static port (`30000–32767`) on **every node's IP address** in the cluster. External traffic hitting `<Any-Node-IP>:<NodePort>` is routed to the Service's `ClusterIP`, which then load-balances it to the target Pods.
* **Use Case:** Bare-metal clusters (like your `kubeadm` cluster), local development, demos, or custom on-premise load balancers where no cloud provider load balancer integration exists.

### 3. `LoadBalancer`
* **How it works:** Builds on top of `NodePort` and `ClusterIP` by automatically provisioning an external cloud load balancer (such as AWS ELB/ALB, Google Cloud Load Balancer, or Azure Load Balancer) with a dedicated public IP address.
* **Use Case:** Production workloads running on managed cloud Kubernetes platforms (EKS, GKE, AKS) that require direct external internet access on standard ports like `80` or `443`. *(On bare-metal `kubeadm` clusters, a `LoadBalancer` service stays in `<pending>` state unless you install a bare-metal load balancer controller like MetalLB).*

### 4. `ExternalName`
* **How it works:** Maps the Service to an external DNS domain name (e.g., `my.database.example.com`) by returning a DNS `CNAME` record instead of proxying traffic or allocating a `ClusterIP`.
* **Use Case:** Allowing Pods inside the cluster to connect to external services (like a managed cloud RDS database or legacy external API) using a standard internal Kubernetes Service name, making it easy to switch endpoints later without changing application code.

| Service Type | Accessible From | Allocates `ClusterIP`? | Opens Node Port? | Requires Cloud Provider / Add-on? |
| :--- | :--- | :---: | :---: | :---: |
| **`ClusterIP`** | Inside cluster only | Yes | No | No |
| **`NodePort`** | Inside & Outside (`<NodeIP>:<NodePort>`) | Yes | Yes (`30000-32767`) | No |
| **`LoadBalancer`** | Inside & Outside (Public IP) | Yes | Yes | Yes (Cloud or MetalLB) |
| **`ExternalName`** | Inside cluster (DNS `CNAME` alias) | No | No | No |

---

## Single-Line Imperative Command (`kubectl expose`)

Instead of writing a YAML file from scratch, you can create a Service directly from an existing Deployment, ReplicaSet, or Pod in a single command using `kubectl expose`.

### Example 1: Expose a Deployment as a `NodePort` Service
```bash
kubectl expose deployment nginx-deployment --name=nginx-service --type=NodePort --port=80 --target-port=80
```

### Example 2: Expose a Deployment as an Internal `ClusterIP` Service
```bash
kubectl expose deployment nginx-deployment --name=nginx-internal --type=ClusterIP --port=80 --target-port=80
```

### Example 3: Expose a Standalone Pod as a `LoadBalancer` Service
```bash
kubectl expose pod nginx-pod --name=nginx-lb --type=LoadBalancer --port=80 --target-port=80
```

### Flag Breakdown for `kubectl expose`
* `deployment nginx-deployment`: The target resource whose Pod labels Kubernetes automatically copies into the Service's `selector`.
* `--name=nginx-service`: Sets the name of the newly created Service (defaults to the Deployment's name if omitted).
* `--type=NodePort`: Sets the Service type (`ClusterIP`, `NodePort`, or `LoadBalancer`).
* `--port=80`: The port exposed by the Service itself.
* `--target-port=80`: The container port on the backend Pods receiving the traffic.

---

## Quick Verification Commands

```bash
# Apply the YAML manifest
kubectl apply -f service.yaml

# List Services and view ClusterIP / NodePort assignments
kubectl get svc

# Inspect the Service and verify matched Pod IP endpoints
kubectl describe svc nginx-service
kubectl get endpoints nginx-service

# Test connectivity from inside the cluster or via NodePort
curl http://<Node-IP>:30080

# Delete the Service
kubectl delete svc nginx-service
```