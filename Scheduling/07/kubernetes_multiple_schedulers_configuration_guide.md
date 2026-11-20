# Kubernetes Multiple Schedulers Configuration Guide

By default, every Kubernetes cluster runs a single built-in scheduler (`default-scheduler`) that watches for unscheduled Pods and assigns them to nodes.

However, Kubernetes is extensible—you can run **multiple schedulers simultaneously** alongside the default scheduler. This allows specialized workloads (such as batch jobs, machine learning pipelines, or custom bin-packing algorithms) to use custom scheduling logic without affecting standard cluster workloads.

## 1. How Multiple Schedulers Work

1. **Unique Scheduler Name:** Every scheduler instance in the cluster must identify itself with a unique `schedulerName` (e.g., `default-scheduler`, `my-custom-scheduler`).
2. **Pod Routing (`spec.schedulerName`):**
   * If a Pod does **not** specify `spec.schedulerName`, Kubernetes automatically assigns it to `default-scheduler`.
   * If a Pod specifies `spec.schedulerName: my-custom-scheduler`, the default scheduler ignores it, and only `my-custom-scheduler` picks it up and binds it to a node.
3. **Leader Election (High Availability):** When running multiple replicas of a custom scheduler, a dedicated `Lease` lock object ensures only one active replica schedules Pods at a time while standbys wait.

## 2. Step-by-Step: Configuring & Deploying a Custom Scheduler

On a `kubeadm` cluster, the easiest way to run a second scheduler is to deploy another instance of the official `kube-scheduler` binary (with custom configuration) as a **Deployment** inside `kube-system`.

### Step 1: Create RBAC Permissions (`custom-scheduler-rbac.yaml`)

A custom scheduler needs permissions to read nodes/Pods, create `Binding` objects, manage `Lease` locks for leader election, and emit events.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-custom-scheduler
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: my-custom-scheduler-as-kube-scheduler
subjects:
  - kind: ServiceAccount
    name: my-custom-scheduler
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: system:kube-scheduler
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: my-custom-scheduler-as-volume-scheduler
subjects:
  - kind: ServiceAccount
    name: my-custom-scheduler
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: system:volume-scheduler
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-custom-scheduler-extension-apiserver-authentication-reader
  namespace: kube-system
subjects:
  - kind: ServiceAccount
    name: my-custom-scheduler
    namespace: kube-system
roleRef:
  kind: Role
  name: extension-apiserver-authentication-reader
  apiGroup: rbac.authorization.k8s.io
```

* **Why built-in ClusterRoles work:** Kubernetes already includes `system:kube-scheduler` and `system:volume-scheduler` ClusterRoles with all required permissions; binding them to your `ServiceAccount` grants full scheduling access cleanly.

### Step 2: Create the Scheduler Configuration (`custom-scheduler-config.yaml`)

Modern Kubernetes versions configure `kube-scheduler` using a **`KubeSchedulerConfiguration`** file stored inside a `ConfigMap`.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-custom-scheduler-config
  namespace: kube-system
data:
  my-scheduler-config.yaml: |
    apiVersion: kubescheduler.config.k8s.io/v1
    kind: KubeSchedulerConfiguration
    profiles:
      - schedulerName: my-custom-scheduler
    leaderElection:
      leaderElect: true
      resourceNamespace: kube-system
      resourceName: my-custom-scheduler-lock
```

#### Key Configuration Fields Explained

* **`profiles.schedulerName: my-custom-scheduler`**
  * Defines the exact name Pods must reference in `spec.schedulerName` to be handled by this scheduler.
* **`leaderElection.leaderElect: true`**
  * Enables leader election so multiple replicas of `my-custom-scheduler` don't fight over the same Pods.
* **`leaderElection.resourceName: my-custom-scheduler-lock`**
  * **Critical:** Must be a **unique** Lease name different from `kube-scheduler` (the default scheduler's lock), otherwise your custom scheduler will collide with the default scheduler!

### Step 3: Deploy the Custom Scheduler (`custom-scheduler-deployment.yaml`)

Check your cluster's `kube-scheduler` image version first (`kubectl get pod -n kube-system -l component=kube-scheduler -o jsonpath='{.items[0].spec.containers[0].image}'`) and use that matching tag.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-custom-scheduler
  namespace: kube-system
  labels:
    component: scheduler
    tier: control-plane
spec:
  replicas: 1
  selector:
    matchLabels:
      component: scheduler
      app: my-custom-scheduler
  template:
    metadata:
      labels:
        component: scheduler
        app: my-custom-scheduler
    spec:
      serviceAccountName: my-custom-scheduler
      containers:
        - name: kube-scheduler
          image: registry.k8s.io/kube-scheduler:v1.37.0
          command:
            - kube-scheduler
            - --config=/etc/kubernetes/my-scheduler/my-scheduler-config.yaml
            - --v=2
          livenessProbe:
            httpGet:
              path: /healthz
              port: 10259
              scheme: HTTPS
            initialDelaySeconds: 15
          readinessProbe:
            httpGet:
              path: /healthz
              port: 10259
              scheme: HTTPS
          volumeMounts:
            - name: config-volume
              mountPath: /etc/kubernetes/my-scheduler
      volumes:
        - name: config-volume
          configMap:
            name: my-custom-scheduler-config
```

## 3. Assigning a Pod to the Custom Scheduler

Once `my-custom-scheduler` is running in `kube-system`, configure any Pod (or Deployment `spec.template.spec`) to use it by setting **`spec.schedulerName`**.

### Complete `custom-scheduled-pod.yaml` Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: custom-scheduled-nginx
  labels:
    app: nginx
spec:
  schedulerName: my-custom-scheduler
  containers:
    - name: nginx
      image: nginx:1.27
      ports:
        - containerPort: 80
```

* **What happens if `my-custom-scheduler` is down or misspelled?** The Pod remains in a **`Pending`** state indefinitely because `default-scheduler` will not touch Pods assigned to another `schedulerName`.

## 4. Verification & Troubleshooting Commands

```bash
# 1. Apply RBAC, ConfigMap, and Deployment
kubectl apply -f custom-scheduler-rbac.yaml
kubectl apply -f custom-scheduler-config.yaml
kubectl apply -f custom-scheduler-deployment.yaml

# 2. Verify the custom scheduler Pod is Running
kubectl get pods -n kube-system -l app=my-custom-scheduler

# 3. Check the Lease lock created for your custom scheduler
kubectl get leases -n kube-system

# 4. Deploy the test Pod using your custom scheduler
kubectl apply -f custom-scheduled-pod.yaml

# 5. Verify via Events which scheduler actually scheduled the Pod
kubectl get events --field-selector involvedObject.name=custom-scheduled-nginx
# Look for: "Successfully assigned default/custom-scheduled-nginx to <node-name>" from source "my-custom-scheduler"

# 6. Check custom scheduler logs if a Pod stays Pending
kubectl logs -n kube-system -l app=my-custom-scheduler
```