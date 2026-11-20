# Validating & Mutating Admission Controllers: Deep-Dive Guide

While built-in admission controllers (like `LimitRanger` and `NamespaceLifecycle`) are compiled directly into the `kube-apiserver` binary, Kubernetes allows you to extend admission control dynamically at runtime using **Mutating Admission Webhooks** and **Validating Admission Webhooks** (as well as native **ValidatingAdmissionPolicies**).

Together, they let you intercept, modify, and enforce custom policies on any Kubernetes API request before it is saved to `etcd`.

---

## 1. End-to-End Execution Order

When a client sends a write request (`CREATE`, `UPDATE`, `DELETE`, `CONNECT`) to `kube-apiserver`, it passes through both admission phases in strict sequence:

```
API Request (e.g., kubectl apply -f pod.yaml)
       │
       ▼
[1] Authentication & Authorization (RBAC)
       │
       ▼
[2] Mutating Admission Phase  ──► Runs SEQUENTIALLY (Built-in + MutatingWebhookConfiguration)
       │                          • Modifies/patches the object (JSONPatch)
       │                          • May re-invoke webhooks if an earlier webhook mutated the object
       ▼
[3] Schema Validation         ──► Validates mutated YAML against Kubernetes OpenAPI schema
       │
       ▼
[4] Validating Admission Phase ─► Runs IN PARALLEL (Built-in + ValidatingWebhookConfiguration + CEL Policies)
       │                          • Read-only inspection: returns Allowed = true or false
       │                          • If ANY single validator returns false, request is REJECTED
       ▼
[5] Persist to etcd           ──► Object is written to cluster database
```

### Why Mutating Always Runs Before Validating
If a **Mutating** webhook injects a required label (e.g., `owner: platform-team`) or a default sidecar container into a Pod, the **Validating** webhook must inspect the *final* mutated Pod—not the incomplete manifest originally submitted by the user.

---

## 2. Mutating Admission Controllers (`MutatingWebhookConfiguration`)

A **Mutating Admission Controller** intercepts incoming objects and returns a **JSON Patch** (`RFC 6902`) telling `kube-apiserver` which fields to add, replace, or remove before persisting the object.

### Real-World Use Cases
* **Service Mesh Sidecar Injection (Istio / Linkerd):** Automatically injects an Envoy proxy container and init-containers into every Pod created inside labeled namespaces.
* **Secret Injection (HashiCorp Vault):** Injects agent containers and volume mounts to fetch secrets dynamically at Pod startup.
* **Default Labels & Annotations:** Automatically stamps `team`, `cost-center`, or `managed-by` labels onto every new Deployment or Namespace.
* **Image Registry Rewriting:** Rewrites public Docker Hub image paths (e.g., `nginx:1.27`) to point to an internal private mirror (`registry.internal.corp/library/nginx:1.27`).

### Complete `MutatingWebhookConfiguration` YAML Example

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: sidecar-injector-webhook
webhooks:
  - name: inject.sidecar.example.com
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Fail
    reinvocationPolicy: Never
    namespaceSelector:
      matchLabels:
        sidecar-injection: enabled
    objectSelector:
      matchExpressions:
        - key: skip-injection
          operator: DoesNotExist
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
        scope: "Namespaced"
    clientConfig:
      service:
        name: sidecar-injector-svc
        namespace: webhook-system
        path: "/mutate"
        port: 443
      caBundle: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t... # Base64-encoded CA certificate
```

---

## 3. Validating Admission Controllers (`ValidatingWebhookConfiguration`)

A **Validating Admission Controller** inspects the final object after all mutations and schema checks complete. It **cannot** modify the object—it only decides whether the request is allowed or denied.

### Real-World Use Cases
* **Image Security Enforcement:** Blocks Pods using the `:latest` tag or images pulled from unapproved public registries.
* **Security Context Hardening:** Rejects Pods running as `root` (`runAsNonRoot: true` required) or requesting `privileged: true`.
* **Naming & Labeling Standards:** Rejects Deployments or Services that lack mandatory `cost-center` or `environment` labels.
* **Ingress Host Collision Prevention:** Blocks creating an `Ingress` if another namespace already claims the exact same hostname.

### Complete `ValidatingWebhookConfiguration` YAML Example

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: pod-security-validator
webhooks:
  - name: validate.pods.example.com
    admissionReviewVersions: ["v1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Fail
    matchPolicy: Equivalent
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system", "kube-public", "webhook-system"]
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
        scope: "Namespaced"
    clientConfig:
      service:
        name: pod-validator-svc
        namespace: webhook-system
        path: "/validate"
        port: 443
      caBundle: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t... # Base64-encoded CA certificate
```

---

## 4. Statement-by-Statement Breakdown of Webhook Fields

* **`webhooks[].name`**: Must be a fully qualified domain name (e.g., `validate.pods.example.com`) that uniquely identifies the webhook.
* **`admissionReviewVersions: ["v1"]`**: Specifies which `AdmissionReview` API versions the webhook server understands (`v1` is standard).
* **`sideEffects: None`**: Declares whether calling the webhook produces external side effects (must be `None` or `NoneOnDryRun` so `kubectl apply --dry-run=server` works safely).
* **`failurePolicy`**: Controls what `kube-apiserver` does if the webhook server is unreachable, crashes, or times out:
  * **`Fail`** *(Recommended for security)*: Rejects the API request immediately (fail-closed).
  * **`Ignore`**: Bypasses the webhook and allows the API request through (fail-open).
* **`timeoutSeconds: 5`**: Maximum seconds (`1` to `30`, default `10`) `kube-apiserver` waits for the webhook to respond before triggering `failurePolicy`.
* **`reinvocationPolicy`** *(Mutating webhooks only)*:
  * **`Never`** *(Default)*: Calls the mutating webhook at most once per request.
  * **`IfNeeded`**: Calls the webhook a second time if a *later* mutating plugin modified the object after this webhook already ran.
* **`namespaceSelector`**: Filters requests based on labels on the target **Namespace** (note: always exclude `kube-system` so a broken webhook never locks out critical control-plane Pods!).
* **`objectSelector`**: Filters requests based on labels on the target **Object** itself (e.g., only mutate Pods with `inject: "true"`).
* **`rules`**: Specifies exact API targets (`apiGroups`, `apiVersions`, `operations` like `CREATE`/`UPDATE`/`DELETE`, and `resources` like `pods` or `deployments`).
* **`clientConfig`**: Defines how `kube-apiserver` connects to the webhook server over **mandatory HTTPS (TLS)**:
  * **`service`**: Points to an internal Kubernetes `Service` (`name`, `namespace`, `path`, `port`).
  * **`url`**: Alternative to `service` for webhooks hosted outside the cluster (e.g., `https://policy.corp.internal:8443/validate`).
  * **`caBundle`**: Base64-encoded PEM CA certificate used by `kube-apiserver` to verify the webhook server's TLS certificate.

---

## 5. Under the Hood: `AdmissionReview` JSON Payloads

`kube-apiserver` communicates with webhook servers using `AdmissionReview` JSON objects over HTTPS `POST`.

### 1. Request Sent by `kube-apiserver` to Webhook
```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "request": {
    "uid": "705ab4f5-6393-11e8-b7cc-42010a800002",
    "kind": { "group": "", "version": "v1", "kind": "Pod" },
    "operation": "CREATE",
    "namespace": "default",
    "userInfo": { "username": "kubernetes-admin" },
    "object": {
      "metadata": { "name": "nginx-pod" },
      "spec": { "containers": [{ "name": "nginx", "image": "nginx:latest" }] }
    }
  }
}
```

### 2. Response from a **Validating** Webhook (Rejecting `:latest` Tag)
```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "705ab4f5-6393-11e8-b7cc-42010a800002",
    "allowed": false,
    "status": {
      "code": 403,
      "message": "Denied: container image 'nginx:latest' must not use the ':latest' tag."
    }
  }
}
```

### 3. Response from a **Mutating** Webhook (Adding a Label via JSONPatch)
```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "705ab4f5-6393-11e8-b7cc-42010a800002",
    "allowed": true,
    "patchType": "JSONPatch",
    "patch": "W3sib3AiOiAiYWRkIiwgInBhdGgiOiAiL21ldGFkYXRhL2xhYmVscy9lbnYiLCAidmFsdWUiOiAicHJvZCJ9XQ=="
  }
}
```
*(The base64 `patch` above decodes to `[{"op": "add", "path": "/metadata/labels/env", "value": "prod"}]`).*

---

## 6. Native Alternative: `ValidatingAdmissionPolicy` (CEL — No Webhook Server Needed)

Starting in Kubernetes `v1.30+` (GA), you can enforce custom validation rules directly inside `kube-apiserver` using **Common Expression Language (CEL)**—eliminating the operational overhead of deploying, securing, and maintaining a separate webhook server and TLS certificates.

### Example: Block `:latest` Image Tags Using Native CEL
```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: disallow-latest-tag
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: "object.spec.containers.all(c, !c.image.endsWith(':latest'))"
      message: "Container images must use a specific version tag, not ':latest'."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: disallow-latest-tag-binding
spec:
  policyName: disallow-latest-tag
  validationActions: ["Deny"]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system"]
```

---

## 7. Quick Comparison: Mutating vs. Validating

| Feature | Mutating Admission Controller | Validating Admission Controller |
| :--- | :--- | :--- |
| **Can Modify Objects?** | **Yes** (returns `JSONPatch`) | **No** (read-only `allowed: true/false`) |
| **Execution Order** | **Sequential** (one after another) | **Parallel** (simultaneous) |
| **API Resources** | `MutatingWebhookConfiguration` | `ValidatingWebhookConfiguration` & `ValidatingAdmissionPolicy` |
| **Typical Use Cases** | Injecting sidecars, setting default labels, rewriting image registries | Enforcing security rules, blocking `:latest` tags, validating quotas |

---

## 8. Inspection & Troubleshooting Commands

```bash
# List all active Mutating and Validating webhook configurations
kubectl get mutatingwebhookconfigurations
kubectl get validatingwebhookconfigurations

# List native CEL ValidatingAdmissionPolicies and bindings
kubectl get validatingadmissionpolicies
kubectl get validatingadmissionpolicybindings

# Inspect a specific webhook's rules, failurePolicy, and target service
kubectl describe validatingwebhookconfiguration pod-security-validator

# Emergency recovery: delete a broken webhook with failurePolicy: Fail that is blocking cluster operations
kubectl delete validatingwebhookconfiguration <webhook-name>
```