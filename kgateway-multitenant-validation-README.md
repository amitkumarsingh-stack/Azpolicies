# kgateway Multi-Tenant AKS Validation Test Plan

## 1. Purpose

This document records the multi-tenant ingress validation performed for a test environment using:

- AKS Kubernetes 1.35.5
- Azure CNI Overlay
- Calico NetworkPolicy
- kgateway 2.4.2
- Internal Azure Load Balancer
- HTTPS ingress on port 443
- Three tenant namespaces: `team-a`, `team-b`, `team-c`
- Shared/platform namespace: `core`
- Shared Gateway: `shared-gateway`

The objective was to validate tenant isolation and the security boundaries between:

1. Kubernetes RBAC
2. Gateway API / kgateway
3. `ReferenceGrant`
4. NetworkPolicy
5. TLS/SNI
6. Resource quotas
7. Shared ingress/data-plane behavior

---

## 2. Test Architecture

```text
                         AKS
                          |
                  +-------+-------+
                  |   core        |
                  |               |
                  | shared-gateway|
                  | kgateway/Envoy|
                  +-------+-------+
                          |
             +------------+------------+
             |            |            |
          team-a        team-b       team-c
             |            |            |
          app-a         app-b        app-c
          svc-a         svc-b       svc-c
             |            |            |
          HTTPRoute     HTTPRoute    HTTPRoute
```

The Gateway is platform-owned in `core`.

Tenant applications and routes are namespace-scoped.

---

## 3. Security Model

The validation intentionally used multiple independent controls.

```text
Client
  |
  v
Internal Azure Load Balancer
  |
  v
kgateway / Envoy (core)
  |
  +---- Gateway API route authorization
  |
  +---- ReferenceGrant for cross-namespace backend references
  |
  v
Tenant Service
  |
  v
Tenant Pod

Additional controls:

RBAC             -> who can modify Kubernetes resources
NetworkPolicy    -> which pods/namespaces can communicate
ResourceQuota    -> how much compute a tenant can consume
TLS/SNI          -> certificate/hostname isolation
```

A key architectural finding is that NetworkPolicy sees backend traffic from the Envoy/krgateway data plane in `core`. Therefore, an HTTP request originating from a client in the context of tenant A and routed by Envoy to tenant B is a network connection from `core` to `team-b`, not a direct `team-a` pod-to-`team-b` pod connection.

---

# 4. Tests Performed

## Test 1 — Baseline tenant application connectivity

### Objective

Verify that each tenant application and Service works independently before testing ingress isolation.

### Tested

- `team-a` application
- `team-b` application
- `team-c` application
- Direct Service connectivity

### Expected

Each application returned a unique tenant response:

```text
TENANT-A
TENANT-B
TENANT-C
```

### Result

**PASS**

---

## Test 2 — Shared HTTPS Gateway

### Objective

Verify that kgateway can expose multiple tenants through one internal HTTPS Gateway.

### Configuration

```text
core/shared-gateway
       |
       +-- team-a hostname -> team-a Service
       +-- team-b hostname -> team-b Service
       +-- team-c hostname -> team-c Service
```

### Test

HTTPS requests were sent to the internal Load Balancer using SNI/hostname resolution.

Example:

```bash
curl -sk --resolve <TEAM_A_HOST>:443:<INTERNAL_GATEWAY_IP> \
  https://<TEAM_A_HOST>/
```

Equivalent requests were made for B and C.

### Expected

```text
TEAM-A hostname -> TENANT-A
TEAM-B hostname -> TENANT-B
TEAM-C hostname -> TENANT-C
```

### Result

**PASS**

---

# 5. Test 3 — NetworkPolicy Tenant Isolation

## Objective

Verify that tenant pods cannot directly communicate with other tenant pods.

### Target matrix

```text
             DEST
           A     B     C
SRC A      ✓     ✗     ✗
SRC B      ✗     ✓     ✗
SRC C      ✗     ✗     ✓

core -> A/B/C = ✓
DNS from tenants = ✓
```

### Tested

- A -> A
- A -> B
- A -> C
- B -> A
- B -> B
- B -> C
- C -> A
- C -> B
- C -> C
- DNS
- Gateway/data-plane -> tenant Services

### Expected

Same-tenant communication:

```text
ALLOW
```

Cross-tenant direct pod/service communication:

```text
DENY
```

Gateway/data-plane traffic:

```text
ALLOW
```

### Result

**PASS**

A NetworkPolicy configuration issue initially caused an ingress `503`. The policy was corrected so that the `core` namespace/data plane could reach the tenant backend.

---

# 6. Test 4 — Cross-Namespace HTTPRoute Without ReferenceGrant

## Objective

Verify that a tenant cannot reference another tenant's Service through Gateway API without authorization.

### Attack scenario

An HTTPRoute in `team-a` attempted to reference:

```text
team-b/team-b-app
```

The backend reference explicitly specified:

```yaml
backendRefs:
- name: team-b-app
  namespace: team-b
  port: 80
```

### Important

The namespace must be explicitly specified.

If `namespace` is omitted, Gateway API treats the backend reference as being in the HTTPRoute's namespace. That produces a different failure and does not properly test cross-namespace authorization.

### Expected without ReferenceGrant

The route backend reference should not resolve.

Typical condition:

```text
ResolvedRefs: False
```

with a reason indicating that the reference is not permitted.

The request must not return:

```text
TENANT-B
```

### Result

**PASS**

---

# 7. Test 5 — ReferenceGrant Allows Specific Cross-Namespace Access

## Objective

Verify that a tightly scoped `ReferenceGrant` permits the intended cross-namespace reference.

### ReferenceGrant

Created in:

```text
team-b
```

with the equivalent configuration:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: ReferenceGrant
metadata:
  name: allow-team-a
  namespace: team-b
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: team-a
  to:
  - group: ""
    kind: Service
```

### Meaning

Only an HTTPRoute from:

```text
team-a
```

is authorized to reference Services in:

```text
team-b
```

### Verification

The route changed from unresolved to resolved.

Expected:

```text
ResolvedRefs: True
```

The HTTPS request returned:

```text
TENANT-B
```

### Result

**PASS**

---

# 8. Test 6 — Reverse ReferenceGrant Isolation

## Objective

Verify that the grant above does NOT create unrestricted cross-namespace access.

### Attack scenario

An HTTPRoute in:

```text
team-b
```

attempted to reference:

```text
team-a/team-a-app
```

### Expected

The existing grant in `team-b` should not authorize:

```text
team-b -> team-a
```

The reference should remain unresolved.

The request must not return:

```text
TENANT-A
```

### Result

**PASS**

### Security conclusion

The `ReferenceGrant` was demonstrated to be directional and namespace-scoped.

---

# 9. Test 7 — Hostname Hijacking

## Objective

Verify that one tenant cannot successfully claim another tenant's hostname and redirect that hostname to its own backend.

### Attack scenario

`team-b` created an HTTPRoute attempting to claim the hostname already used by `team-a`.

The route pointed to the `team-b` backend.

### Test

The original team-A hostname was requested through the internal Gateway.

Example:

```bash
curl -sk --resolve <TEAM_A_HOST>:443:<INTERNAL_GATEWAY_IP> \
  https://<TEAM_A_HOST>/
```

### Expected security property

The `team-b` route must not successfully hijack the tenant-A hostname.

### Result

**PASS**

---

# 10. Test 8 — Tenant RBAC Isolation

## Objective

Verify that tenants cannot modify resources belonging to other tenants.

Dedicated test ServiceAccounts were created:

```text
team-a/rbac-test
team-b/rbac-test
team-c/rbac-test
```

The `team-a/rbac-test` identity was tested.

### Initial baseline

Before permissions were granted, the identity could not access tenant resources.

### Tenant-scoped permissions

A Role/RoleBinding was created in `team-a` allowing the test identity to manage HTTPRoutes in its own namespace.

Equivalent permissions included:

```text
get
list
watch
create
update
patch
delete
```

for:

```text
httproutes.gateway.networking.k8s.io
```

in `team-a`.

### Verification

Expected:

```text
team-a HTTPRoute -> yes
team-b HTTPRoute -> no
team-b Service update -> no
```

### Result

**PASS**

---

# 11. Test 9 — Shared Gateway RBAC Protection

## Objective

Verify that a tenant cannot modify the platform-owned shared Gateway.

Tested as:

```text
system:serviceaccount:team-a:rbac-test
```

against the `core` namespace.

### Operations tested

```text
update Gateway
delete Gateway
create Gateway
```

### Expected

```text
no
no
no
```

### Result

**PASS**

---

# 12. Test 10 — GatewayClass RBAC Protection

## Objective

Verify that a tenant cannot modify the platform-owned GatewayClass.

### Operations tested

```text
update GatewayClass
delete GatewayClass
create GatewayClass
```

### Expected

```text
no
no
no
```

At the same time, the tenant retained permission to create its own HTTPRoutes.

### Result

**PASS**

### Security boundary

```text
team-a identity

team-a HTTPRoutes      -> ALLOW
team-b resources       -> DENY
core Gateway           -> DENY
GatewayClass           -> DENY
```

---

# 13. Test 11 — ResourceQuota Enforcement

## Objective

Verify that a tenant cannot exceed its assigned compute quota.

A test `ResourceQuota` was applied to `team-a` with limits for:

```text
CPU requests
Memory requests
CPU limits
Memory limits
Pod count
```

A deliberately oversized test Deployment was then submitted.

Example requested resources:

```yaml
resources:
  requests:
    cpu: "2"
    memory: 3Gi
  limits:
    cpu: "2"
    memory: 3Gi
```

These exceeded the test namespace quota.

### Expected

The Pod should be rejected by quota admission.

An event similar to:

```text
exceeded quota
```

was expected.

### Result

**PASS**

The test workload was subsequently removed.

---

# 14. Test 12 — Backend Failure Isolation

## Objective

Verify that one tenant's backend failure does not break other tenants.

### Test

The `team-a` application Deployment was temporarily scaled to zero.

Example:

```bash
kubectl scale deployment <TEAM_A_DEPLOYMENT> \
  -n team-a \
  --replicas=0
```

### Requests

```text
team-a -> expected failure
team-b -> TENANT-B
team-c -> TENANT-C
```

### Result

**PASS**

`team-a` failed as expected while B and C remained healthy.

The `team-a` Deployment was restored afterward.

---

# 15. Test 13 — TLS/SNI Certificate Isolation

## Objective

Verify that the shared HTTPS Gateway presents the appropriate certificate based on SNI.

### Tested

Each tenant hostname was tested with:

```bash
openssl s_client \
  -connect <INTERNAL_GATEWAY_IP>:443 \
  -servername <TEAM_HOST> \
  </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer
```

### Expected

```text
team-a hostname -> team-a certificate
team-b hostname -> team-b certificate
team-c hostname -> team-c certificate
```

### Result

**PASS**

---

# 16. Test 14 — Data-Plane Pod Failure

## Objective

Verify that failure of one kgateway/Envoy data-plane pod does not permanently interrupt the shared Gateway.

### Test

One data-plane pod was deleted while another replica remained available.

The replacement pod was observed with:

```bash
kubectl get pods -n core -w
```

Traffic was continuously tested against a tenant HTTPS endpoint.

### Expected

The remaining data-plane replica continued serving traffic and Kubernetes recreated the failed pod.

### Result

**PASS**

---

# 17. Tests Not Performed

The following tests were intentionally skipped or left for a future phase.

## Node-level failure / HA topology

We did not perform:

- AKS node drain
- Node failure simulation
- PDB disruption testing
- Topology-spread validation

Reason: the test was intentionally stopped before this phase.

## Gateway `allowedRoutes` deep validation

The Gateway listener `allowedRoutes` configuration was inspected, but no configuration changes or destructive attachment tests were performed as part of the final test run.

## kgateway reference-grant mode hardening

The kgateway reference-grant mode was identified as an area for a future production-hardening review.

---

# 18. Final Security Validation Matrix

| Area | Test | Result |
|---|---|---|
| Application baseline | A/B/C direct connectivity | PASS |
| HTTPS ingress | Shared Gateway routes A/B/C | PASS |
| Network isolation | Cross-tenant direct traffic denied | PASS |
| Gateway access | kgateway reaches tenant backends | PASS |
| ReferenceGrant | A -> B without grant | PASS: denied |
| ReferenceGrant | A -> B with grant | PASS: allowed |
| ReferenceGrant scope | B -> A with A-only grant | PASS: denied |
| Hostname isolation | B attempts A hostname | PASS |
| RBAC | Tenant own namespace | PASS |
| RBAC | Tenant -> other namespace | PASS: denied |
| RBAC | Tenant -> shared Gateway | PASS: denied |
| RBAC | Tenant -> GatewayClass | PASS: denied |
| Resource isolation | ResourceQuota enforcement | PASS |
| Failure isolation | A backend down, B/C healthy | PASS |
| TLS | SNI/certificate isolation | PASS |
| Data-plane HA | One Envoy pod failure | PASS |
| Node HA | Node failure simulation | NOT TESTED |
| PDB/topology | Disruption/topology validation | NOT TESTED |
| Gateway allowedRoutes | Full attachment-policy validation | NOT COMPLETED |

---

# 19. Key Findings

## Finding 1 — ReferenceGrant is a critical cross-namespace security boundary

Without a `ReferenceGrant`, a tenant's HTTPRoute cannot legitimately reference another namespace's Service.

With a specifically scoped grant, the intended reference becomes valid.

The reverse test demonstrated that the grant does not automatically authorize the opposite direction.

## Finding 2 — NetworkPolicy and Gateway API solve different problems

NetworkPolicy controls network connectivity between pods.

Gateway API / `ReferenceGrant` controls whether a Gateway API resource is authorized to reference a resource in another namespace.

They should not be treated as substitutes.

## Finding 3 — Envoy changes the source of backend traffic

For ingress traffic:

```text
client -> Envoy -> tenant Service
```

the backend connection is from Envoy in `core`.

Therefore:

```text
team-a pod -> team-b pod
```

can be denied while:

```text
core/Envoy -> team-b Service
```

is allowed.

This is why the successful `team-a` HTTPRoute -> `team-b` Service test does not contradict the direct tenant-to-tenant NetworkPolicy isolation.

## Finding 4 — Tenant RBAC should remain namespace-scoped

The tested model allows a tenant to manage its own HTTPRoutes while preventing it from modifying:

```text
other tenant namespaces
shared Gateway
GatewayClass
```

This is the desired platform/tenant separation.

## Finding 5 — Resource limits are part of tenant isolation

Network isolation does not protect against resource exhaustion.

ResourceQuota enforcement provides an additional boundary against a noisy tenant consuming unlimited namespace resources.

---

# 20. Recommended Production Guardrails

Before using this pattern for production tenants, validate/document:

1. Tenant namespaces are protected with NetworkPolicies.
2. Platform-owned Gateway and GatewayClass remain inaccessible to tenant identities.
3. Cross-namespace backend references require explicit `ReferenceGrant`.
4. `ReferenceGrant` objects are reviewed as security-sensitive resources.
5. Tenant RBAC remains namespace-scoped.
6. ResourceQuota and LimitRange are defined for every tenant.
7. Tenant workloads have CPU/memory requests and limits.
8. TLS certificates and secrets are namespace-scoped and access-controlled.
9. Gateway listeners have an explicitly reviewed `allowedRoutes` policy.
10. kgateway cross-namespace reference validation is configured appropriately for the production multi-tenant model.
11. Data-plane replicas are sufficient for availability requirements.
12. Pod placement, PDBs, and topology spreading are reviewed before production.
13. Monitoring/alerting covers Gateway, Envoy, route status, backend health, and certificate expiry.
14. A formal negative-test suite is retained and rerun after kgateway/Kubernetes upgrades.

---

# 21. Useful Commands

### Gateway

```bash
kubectl describe gateway shared-gateway -n core
```

### Routes

```bash
kubectl get httproute -A
kubectl describe httproute <ROUTE> -n <NAMESPACE>
```

### ReferenceGrant

```bash
kubectl get referencegrant -A
kubectl describe referencegrant <NAME> -n <NAMESPACE>
```

### NetworkPolicy

```bash
kubectl get networkpolicy -A
kubectl describe networkpolicy <NAME> -n <NAMESPACE>
```

### RBAC

```bash
kubectl auth can-i <VERB> <RESOURCE> \
  --as=system:serviceaccount:<NAMESPACE>:<SERVICEACCOUNT> \
  -n <NAMESPACE>
```

### ResourceQuota

```bash
kubectl get resourcequota -A
kubectl describe resourcequota <NAME> -n <NAMESPACE>
```

### Data plane

```bash
kubectl get pods -A -o wide | grep -Ei 'envoy|kgateway'
```

### HTTPS route test

```bash
curl -sk --resolve <HOST>:443:<INTERNAL_GATEWAY_IP> \
  https://<HOST>/
```

### TLS/SNI test

```bash
openssl s_client \
  -connect <INTERNAL_GATEWAY_IP>:443 \
  -servername <HOST> \
  </dev/null 2>/dev/null | \
  openssl x509 -noout -subject -issuer
```

---

# 22. Overall Result

The completed test suite demonstrated the intended separation of concerns for the multi-tenant kgateway design:

```text
                         PLATFORM
                            |
                       core namespace
                            |
                     shared Gateway
                            |
                  +---------+---------+
                  |         |         |
                team-a    team-b    team-c
                  |         |         |
               tenant    tenant    tenant
               resources resources resources
```

The strongest demonstrated security boundaries were:

```text
Tenant -> Tenant direct network traffic       DENIED
Tenant -> Other namespace RBAC                 DENIED
Tenant -> Shared Gateway RBAC                  DENIED
Tenant -> GatewayClass RBAC                    DENIED
Cross-namespace BackendRef without grant       DENIED
Cross-namespace BackendRef with grant          ALLOWED
Unrelated reverse ReferenceGrant direction     DENIED
Hostname hijacking                             DENIED
Resource quota exceeded                        DENIED
```

The shared Gateway can therefore provide centralized HTTPS ingress while retaining multiple independent tenant security controls.

---

## Appendix — Test Status

**Completed:** 14 validation areas

**Skipped intentionally:** node-level HA/PDB/topology testing

**Stopped at:** Gateway listener attachment-policy / final kgateway configuration hardening review
