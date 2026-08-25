# NGINX Ingress Proxy Annotations → Native Gateway API

## Purpose

This document maps commonly used NGINX Ingress `proxy-*` timeout and retry annotations to the closest **native Kubernetes Gateway API** concepts.

The scope is deliberately limited to **Gateway API resources and fields**. Controller-specific APIs such as kgateway `BackendConfigPolicy`, Istio `VirtualService`, Traefik `Middleware`, or NGINX Gateway Fabric `ProxySettingsPolicy` are excluded.

This distinction matters because Gateway API defines a common API model, but individual implementations may support different subsets of the API.

---

## Executive summary

| NGINX annotation | Native Gateway API equivalent | Assessment |
|---|---|---|
| `proxy-connect-timeout` | None | ❌ No native equivalent |
| `proxy-send-timeout` | None | ❌ No native equivalent |
| `proxy-read-timeout` | `HTTPRoute.spec.rules[].timeouts.backendRequest` | ⚠️ Closest, but not identical |
| `proxy-next-upstream-timeout` | `backendRequest` + Gateway API `retry` | ⚠️ Closest, but not identical |
| `proxy-next-upstream-tries` | `retry.attempts` | ⚠️ Extended/Experimental |
| `proxy-next-upstream` | `retry.codes` / retry configuration | ⚠️ Extended/Experimental |

### Important conclusion

There is **no exact, universally portable native Gateway API replacement** for all NGINX proxy timeout/retry annotations.

The Gateway API timeout model intentionally does not expose separate `connect`, `send`, and `read` timeout fields.

The standardized model is broader:

```yaml
timeouts:
  request: 30s
  backendRequest: 10s
```

Gateway API retry is a separate capability:

```yaml
retry:
  attempts: 3
  backoff: 1s
  codes:
    - 502
    - 503
    - 504
```

However, retry is an **Extended/Experimental** Gateway API feature and controller support varies.

---

# 1. `proxy-connect-timeout`

### NGINX

```yaml
nginx.ingress.kubernetes.io/proxy-connect-timeout: "5"
```

Controls the time allowed to establish a connection to the upstream/backend.

### Native Gateway API

**No equivalent.**

Gateway API does not define a dedicated backend connection-establishment timeout.

Therefore, this cannot be represented exactly with a portable `Gateway`, `HTTPRoute`, or other standard Gateway API resource.

**Migration result:**

```text
proxy-connect-timeout
        ↓
No native Gateway API equivalent
```

---

# 2. `proxy-send-timeout`

### NGINX

```yaml
nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
```

NGINX uses this to control the timeout between successive write operations while sending the request to the upstream.

This is not simply a total request-upload duration.

### Native Gateway API

**No exact equivalent.**

Gateway API does not expose a separate backend `send` timeout.

Do not treat:

```yaml
timeouts:
  backendRequest: 30s
```

as an exact replacement. `backendRequest` has broader semantics.

**Migration result:**

```text
proxy-send-timeout
        ↓
No native Gateway API equivalent
```

---

# 3. `proxy-read-timeout`

### NGINX

```yaml
nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
```

NGINX's `proxy_read_timeout` controls the time between successive read operations from the upstream.

It is therefore not exactly the same as "maximum total backend response time."

### Native Gateway API

The closest Gateway API concept is:

```yaml
timeouts:
  backendRequest: 30s
```

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example
spec:
  parentRefs:
    - name: example-gateway
  rules:
    - backendRefs:
        - name: example-service
          port: 8080
      timeouts:
        backendRequest: 30s
```

### Semantic difference

`backendRequest` represents the Gateway → backend request/response operation more broadly. It is not specifically an "interval between upstream reads" setting.

**Migration result:**

```text
proxy-read-timeout
        ↓
timeouts.backendRequest
        ↓
Closest native Gateway API equivalent
```

**Assessment: ⚠️ Approximate, not 1:1.**

---

# 4. `proxy-next-upstream-timeout`

### NGINX

```yaml
nginx.ingress.kubernetes.io/proxy-next-upstream-timeout: "30"
```

Controls the amount of time available for passing a request to another upstream after an upstream failure.

### Native Gateway API

Gateway API's retry model uses:

```yaml
timeouts:
  request: 30s
  backendRequest: 10s

retry:
  attempts: 3
```

The important distinction is:

- `request` is the broader request/response timeout.
- `backendRequest` applies to an individual Gateway → backend attempt.
- `retry` controls retry behavior.

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example
spec:
  parentRefs:
    - name: example-gateway
  rules:
    - backendRefs:
        - name: example-service
          port: 8080
      timeouts:
        request: 30s
        backendRequest: 10s
      retry:
        attempts: 3
```

### Important semantic difference

NGINX's `proxy-next-upstream-timeout` and Gateway API's `backendRequest` are not necessarily identical.

The Gateway API retry model is conceptually:

```text
                 request = 30s
        ┌──────────────────────────────┐
        │                              │
        │ attempt 1 → backendRequest  │
        │ attempt 2 → backendRequest  │
        │ attempt 3 → backendRequest  │
        │                              │
        └──────────────────────────────┘
```

**Migration result:**

```text
proxy-next-upstream-timeout
        ↓
backendRequest + retry
        ↓
Closest native Gateway API model
```

**Assessment: ⚠️ Approximate and dependent on retry support.**

---

# 5. `proxy-next-upstream-tries`

### NGINX

```yaml
nginx.ingress.kubernetes.io/proxy-next-upstream-tries: "3"
```

Controls the maximum number of upstream attempts.

### Native Gateway API

The closest field is:

```yaml
retry:
  attempts: 3
```

Example:

```yaml
retry:
  attempts: 3
```

### Important caveat

Gateway API `retry` is not a Core/Standard-only feature. It is currently an Extended/Experimental capability.

Therefore:

```text
proxy-next-upstream-tries
        ↓
retry.attempts
```

is a good Gateway API mapping, but it should not be assumed to work on every Gateway API implementation.

**Assessment: ⚠️ Extended/Experimental.**

---

# 6. `proxy-next-upstream`

### NGINX

Example:

```yaml
nginx.ingress.kubernetes.io/proxy-next-upstream: "error timeout http_502 http_503 http_504"
```

Controls the conditions under which NGINX attempts another upstream.

### Native Gateway API

The closest standardized model is the Gateway API retry configuration, including HTTP status codes:

```yaml
retry:
  attempts: 3
  codes:
    - 502
    - 503
    - 504
```

Example:

```yaml
retry:
  attempts: 3
  codes:
    - 502
    - 503
    - 504
```

### Semantic difference

NGINX supports conditions such as:

```text
error
timeout
http_502
http_503
http_504
```

Gateway API does not expose an exact one-to-one representation of every NGINX retry condition.

**Migration result:**

```text
proxy-next-upstream
        ↓
retry.codes + retry configuration
        ↓
Closest native Gateway API model
```

**Assessment: ⚠️ Extended/Experimental and not 1:1.**

---

# 7. Recommended native Gateway API representation

If the original NGINX configuration is conceptually:

```text
connect timeout = 5s
send timeout    = 30s
read timeout    = 30s
upstream retry timeout = 30s
upstream tries = 3
retry on 502/503/504
```

the closest Gateway API representation is:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example
spec:
  parentRefs:
    - name: example-gateway

  rules:
    - backendRefs:
        - name: example-service
          port: 8080

      timeouts:
        request: 30s
        backendRequest: 10s

      retry:
        attempts: 3
        backoff: 1s
        codes:
          - 502
          - 503
          - 504
```

This is a **semantic approximation**, not a literal conversion of the NGINX configuration.

There is no native Gateway API representation for:

```text
connect timeout
send timeout
```

and the `read` and retry timeout semantics are broader/different from the NGINX directives.

---

# 8. Native Gateway API portability across the four controllers

For a multi-controller environment, separate **API definition** from **implementation support**.

| Feature | kgateway | Istio | Traefik | NGINX Gateway Fabric |
|---|---:|---:|---:|---:|
| `timeouts.request` | ✅ | ✅ | ⚠️ Verify/version dependent | ❌ |
| `timeouts.backendRequest` | ✅ | ✅ | ⚠️ Verify/version dependent | ❌ |
| `retry.attempts` | ✅ | ⚠️ Version/CRD dependent | ⚠️ Gateway API support varies | ❌ |
| `retry.codes` | ✅ | ⚠️ Version/CRD dependent | ⚠️ Limited/implementation dependent | ❌ |
| `retry.backoff` | ✅ | ⚠️ Version/CRD dependent | ⚠️ Implementation dependent | ❌ |
| `connect` timeout | ❌ Native API | ❌ Native API | ❌ Native API | ❌ Native API |
| `send` timeout | ❌ Native API | ❌ Native API | ❌ Native API | ❌ Native API |
| `read` timeout | ⚠️ `backendRequest` approximation | ⚠️ `backendRequest` approximation | ⚠️ `backendRequest` only if supported | ⚠️ `backendRequest` not supported |

The last three rows deliberately refer to **native Gateway API only**. Controller-specific policies are excluded.

---

# 9. Recommended classification for migration tooling

If you are building an automated NGINX Ingress → Gateway API migration tool, use these categories:

### Category A — Direct native Gateway API

No exact examples among the five annotations discussed.

### Category B — Closest native Gateway API equivalent

```text
proxy-read-timeout
    → HTTPRoute.timeouts.backendRequest

proxy-next-upstream-timeout
    → HTTPRoute.timeouts.backendRequest + retry
```

### Category C — Native Gateway API, but Extended/Experimental

```text
proxy-next-upstream-tries
    → HTTPRoute.retry.attempts

proxy-next-upstream
    → HTTPRoute.retry.codes
```

### Category D — No native Gateway API equivalent

```text
proxy-connect-timeout
proxy-send-timeout
```

This classification is safer than automatically converting every NGINX annotation into a Gateway API field.

---

# 10. Bottom line

For **native Gateway API only**:

```text
proxy-connect-timeout
    → ❌ No equivalent

proxy-send-timeout
    → ❌ No equivalent

proxy-read-timeout
    → ⚠️ backendRequest (closest)

proxy-next-upstream-timeout
    → ⚠️ backendRequest + retry (closest)

proxy-next-upstream-tries
    → ⚠️ retry.attempts (Extended/Experimental)

proxy-next-upstream
    → ⚠️ retry.codes / retry configuration (Extended/Experimental)
```

The most important rule for a migration tool is:

> **Do not claim an exact NGINX annotation mapping where Gateway API has only a broader or differently scoped concept.**

In particular, `backendRequest` should be described as the **closest Gateway API equivalent**, not as an exact replacement for `proxy-read-timeout` or `proxy-next-upstream-timeout`.

## References

- Kubernetes Gateway API HTTPRoute API reference: https://gateway-api.sigs.k8s.io/reference/api-types/httproute/
- Gateway API retry GEP: https://gateway-api.sigs.k8s.io/geps/gep-1731/
- Gateway API timeout GEP: https://gateway-api.sigs.k8s.io/geps/gep-1742/
- NGINX Gateway Fabric Gateway API compatibility: https://docs.nginx.com/nginx-gateway-fabric/overview/gateway-api-compatibility/
