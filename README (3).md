# Gateway API Forwarded Headers & Real IP Testing

This test validates forwarded-header and client-IP behavior when using the **native Kubernetes Gateway API** with:

- kgateway
- NGINX Gateway Fabric (NGF)
- Traefik
- Istio

The backend used for observing the request is **httpbin**.

## Goal

The primary goal is to determine:

1. What each Gateway implementation does **by default**.
2. Which behavior is defined by the native Gateway API versus the implementation.
3. How controller-specific configuration changes:
   - `X-Forwarded-For`
   - `X-Forwarded-Port`
   - `X-Forwarded-Proto`
   - `X-Real-IP`
   - real client IP handling
4. Whether client-supplied forwarding headers are trusted, replaced, appended, or ignored.

> **Important:** `X-Forwarded-*`, `X-Real-IP`, trusted proxies, and Real IP handling are generally implementation-specific. They are not portable fields of the standard `Gateway` or `HTTPRoute` API.

## Test Topology

The common baseline topology is:

```text
Client
  |
  v
Gateway
  |
  v
HTTPRoute
  |
  v
httpbin
```

For proxy/LB testing:

```text
Client
  |
  v
Load Balancer / Proxy
  |
  v
Gateway
  |
  v
HTTPRoute
  |
  v
httpbin
```

The same Gateway API configuration and HTTP requests should be used across all four implementations wherever possible.

## Gateway API Configuration

The `Gateway` and `HTTPRoute` should contain only standard Gateway API configuration.

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: httpbin-gateway
spec:
  gatewayClassName: <controller-specific>
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: httpbin
spec:
  parentRefs:
    - name: httpbin-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: httpbin
          port: 80
```

Only `gatewayClassName` is expected to vary between controllers.

## Baseline: No Controller-Specific Configuration

Start with the default configuration.

Do **not** enable options such as:

- `use-forwarded-headers`
- trusted proxy configuration
- trusted proxy hops
- controller-specific Real IP settings

The purpose of this test is to establish the default behavior of each implementation.

### Test 01 — Direct Request

```bash
curl -s http://<GATEWAY-ADDRESS>/headers | jq
```

Record:

- `X-Forwarded-For`
- `X-Forwarded-Port`
- `X-Forwarded-Proto`
- `X-Real-IP`
- other forwarding headers

Also test:

```bash
curl -s http://<GATEWAY-ADDRESS>/anything | jq
```

## Forwarded Header Tests

### Test 02 — Client-Supplied X-Forwarded-For

```bash
curl -s   -H 'X-Forwarded-For: 1.2.3.4'   http://<GATEWAY-ADDRESS>/headers | jq
```

Determine whether the Gateway:

- preserves the supplied value
- replaces it
- appends the actual client address
- removes/ignores it

### Test 03 — Client-Supplied X-Forwarded-Port

```bash
curl -s   -H 'X-Forwarded-Port: 1234'   http://<GATEWAY-ADDRESS>/headers | jq
```

Determine whether the supplied port is preserved, replaced, or ignored.

### Test 04 — Client-Supplied X-Real-IP

```bash
curl -s   -H 'X-Real-IP: 5.6.7.8'   http://<GATEWAY-ADDRESS>/headers | jq
```

Determine whether the value is passed through and/or used for client-IP determination.

### Test 05 — All Headers

```bash
curl -s   -H 'X-Forwarded-For: 1.2.3.4'   -H 'X-Forwarded-Port: 1234'   -H 'X-Real-IP: 5.6.7.8'   http://<GATEWAY-ADDRESS>/headers | jq
```

## X-Forwarded-For Chain Tests

Test a multi-hop XFF value:

```bash
curl -s   -H 'X-Forwarded-For: 1.2.3.4, 10.0.0.1, 10.0.0.2'   http://<GATEWAY-ADDRESS>/headers | jq
```

Interpret the result in terms of:

```text
Original client: 1.2.3.4
Proxy 1:         10.0.0.1
Proxy 2:         10.0.0.2
```

When an actual proxy/LB is present, record both the proxy-generated XFF chain and the Gateway's resulting header.

## Spoofing / Trust Test

This test checks whether an untrusted client can control the apparent client IP.

```bash
curl -s   -H 'X-Forwarded-For: 10.10.10.10'   -H 'X-Real-IP: 10.10.10.10'   http://<GATEWAY-ADDRESS>/headers | jq
```

The result should be evaluated against the configured trust boundary.

The important question is:

> Can an arbitrary client make the application believe that the client IP is an attacker-controlled address?

If a proxy/LB is the trusted source of forwarding headers, repeat the test through that proxy and compare the behavior.

## X-Forwarded-Port and TLS

Test both direct HTTP and TLS-terminated traffic.

Expected observations should distinguish:

```text
X-Forwarded-Port
X-Forwarded-Proto
```

from the Gateway-to-backend connection.

Example topology:

```text
Client
  |
  | HTTPS :443
  v
Load Balancer
  |
  | HTTP :80
  v
Gateway
  |
  v
httpbin
```

Verify whether the original external scheme and port are represented correctly.

## Test Matrix

| Test | kgateway | NGF | Traefik | Istio |
|---|---|---|---|---|
| Direct request | | | | |
| Default XFF behavior | | | | |
| Client-supplied XFF | | | | |
| Client-supplied XF-Port | | | | |
| Client-supplied X-Real-IP | | | | |
| All forwarding headers | | | | |
| Multiple XFF hops | | | | |
| Trusted proxy | | | | |
| Untrusted proxy | | | | |
| Spoofed XFF | | | | |
| TLS termination | | | | |
| Multiple proxy hops | | | | |

## Results to Capture

For every test, capture the headers received by httpbin:

```text
X-Forwarded-For:
X-Forwarded-Port:
X-Forwarded-Proto:
X-Real-IP:
Forwarded:
X-Forwarded-Host:
```

Also record, where available, the TCP peer/remote address.

A useful result format is:

| Field | Value |
|---|---|
| Controller | |
| Gateway API version | |
| GatewayClass | |
| Test | |
| Proxy/LB present | |
| X-Forwarded-For | |
| X-Forwarded-Port | |
| X-Forwarded-Proto | |
| X-Real-IP | |
| Remote address | |
| Expected | |
| Actual | |
| Pass/Fail | |

## Controller-Specific Configuration

After the baseline tests are complete, enable the relevant implementation-specific configuration for each controller.

Examples of configuration areas to investigate:

- **kgateway:** `use-forwarded-headers` and related trusted-proxy/Real IP behavior
- **NGF:** forwarded-header and client-IP behavior supported by the implementation
- **Traefik:** forwarded headers and trusted IP configuration
- **Istio:** Envoy XFF/trusted-hop behavior and downstream client-address handling

Do not put these settings into the portable Gateway API manifest. Keep them separate so the test clearly distinguishes:

```text
Native Gateway API behavior
        +
Controller-specific behavior
```

## Expected Outcome

The final comparison should answer:

1. What forwarding headers are generated by default?
2. What happens when the client supplies those headers?
3. What happens when a trusted proxy supplies them?
4. How are multiple XFF hops interpreted?
5. How is the real client IP determined?
6. How is `X-Forwarded-Port` handled?
7. How does TLS termination affect `X-Forwarded-Proto` and `X-Forwarded-Port`?
8. Can an untrusted client spoof the apparent source IP?
9. Which behaviors are common across implementations?
10. Which behaviors require controller-specific configuration?

## Key Principle

The test should begin with **zero controller-specific forwarded-header/Real-IP configuration**.

That establishes the default behavior.

Then repeat the tests with the relevant controller configuration enabled.

This makes it possible to distinguish:

```text
Gateway API
    |
    +-- Standard routing behavior
    |
    +-- Implementation-specific forwarded-header behavior
    |
    +-- Implementation-specific Real IP / trusted-proxy behavior
```
