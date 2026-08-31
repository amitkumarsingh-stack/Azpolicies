# Managed Istio for AKS vs Self-Managed Istio

## Overview

Azure Kubernetes Service (AKS) provides a managed Istio add-on that
handles much of the Istio control-plane lifecycle for you.

The main trade-off is:

> **Managed Istio reduces operational effort, but gives you less control
> over Istio internals and advanced configuration.**

Self-managed Istio gives you much more flexibility, but you are
responsible for installation, upgrades, compatibility, troubleshooting,
and lifecycle management.

------------------------------------------------------------------------

## Managed Istio vs Self-Managed Istio

  -----------------------------------------------------------------------
  Area                    AKS Managed Istio       Self-Managed Istio
  ----------------------- ----------------------- -----------------------
  Control-plane lifecycle Azure manages it        You manage it

  Istio upgrades          Azure-supported         Full control
                          revisions/lifecycle     

  Istio version           Limited to              Choose upstream version
                          AKS-supported revisions 

  Sidecar mode            Supported               Supported

  Ambient mode            Currently not supported Supported by upstream
                                                  Istio

  Multi-cluster mesh      Currently not supported Supported

  Windows workloads       Not supported           Upstream limitation

  IstioOperator           Blocked                 Supported

  ProxyConfig             Blocked                 Supported

  WorkloadEntry /         Blocked                 Supported
  WorkloadGroup                                   

  WasmPlugin              Blocked                 Supported

  Gateway API             Limited                 Full upstream
                                                  capability

  EnvoyFilter             Allowed, but Azure      Full control
                          support is limited for  
                          problems caused by it   

  MeshConfig              Only supported subset   Full control

  Custom Envoy/Istio      Restricted              Full control
  extensions                                      

  Azure support           Supported by Microsoft  Customer responsibility
                          within the add-on       
                          support boundary        

  AKS integration         Excellent               You manage integration

  Operational burden      Low                     High
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## Important Managed Istio Limitations

### 1. You cannot treat managed Istio as completely "your Istio"

Several advanced Istio configuration mechanisms are blocked in the AKS
managed add-on.

Examples include:

-   `ProxyConfig`
-   `WorkloadEntry`
-   `WorkloadGroup`
-   `IstioOperator`
-   `WasmPlugin`

This matters if your platform team needs deep control over the Istio
installation or Envoy configuration.

With self-managed Istio, you can use the upstream `IstioOperator` API
and control the installation and configuration more directly.

------------------------------------------------------------------------

### 2. Ambient mode is not currently available

The AKS managed Istio add-on currently focuses on the sidecar model.

Conceptually:

``` text
AKS Managed Istio
       |
       +-- Sidecar model  ✅
       |
       +-- Ambient model  ❌
```

If Ambient mode is a strategic requirement, self-managed Istio is
currently the better option.

------------------------------------------------------------------------

### 3. Multi-cluster Istio is a major limitation

The managed add-on currently does not support an Istio multi-cluster
mesh.

For example:

``` text
AKS Cluster A
      |
      | Istio
      |
      +---------- Cluster B
                    |
                   Istio
```

If you need Istio-level cross-cluster service discovery and traffic
management, self-managed Istio provides significantly more flexibility.

This is one of the most important decision points for an enterprise
platform.

------------------------------------------------------------------------

### 4. Gateway API support is limited

The managed add-on does not currently provide the full upstream Istio
Gateway API capability.

If your organization is standardizing on:

``` text
Gateway API
  |
  +-- GatewayClass
  +-- Gateway
  +-- HTTPRoute
  +-- GRPCRoute
```

you should verify the current AKS add-on support before making it a core
platform dependency.

Traditional Istio APIs such as:

``` text
Gateway
VirtualService
DestinationRule
```

remain important for conventional Istio configurations.

------------------------------------------------------------------------

### 5. EnvoyFilter requires caution

`EnvoyFilter` can be used with the managed add-on, but customizations
that introduce problems are outside Microsoft's normal support boundary.

For example:

``` text
EnvoyFilter
    |
    +-- Custom Lua
    +-- Custom Envoy behavior
    +-- Custom extensions
```

These can make troubleshooting more difficult because Azure may not
support issues caused by unsupported customizations.

With self-managed Istio, you have complete control, but you also own the
troubleshooting responsibility.

------------------------------------------------------------------------

### 6. You do not have unlimited Istio version selection

Managed Istio revisions are tied to AKS compatibility and Microsoft's
supported revision lifecycle.

The model is approximately:

``` text
AKS version
    |
    +-- Compatible Istio revisions
             |
             +-- Microsoft-supported lifecycle
```

With self-managed Istio:

``` text
You choose the Istio version
        |
        +-- Your upgrade schedule
        +-- Your compatibility testing
        +-- Your lifecycle management
```

This is a limitation if you need a specific upstream Istio release
immediately.

It is also a benefit if you prefer Azure to manage compatibility and
lifecycle.

------------------------------------------------------------------------

# Where Managed Istio Works Well

For a conventional AKS environment:

``` text
                    Azure
                      |
                AKS Cluster
                      |
             +--------+--------+
             | Managed Istio   |
             |                 |
             | istiod           |
             | ingress gateway  |
             | Envoy sidecars    |
             +--------+--------+
                      |
          +-----------+-----------+
          |           |           |
        svc-a       svc-b       svc-c
```

Managed Istio is a strong choice when you need:

-   Service-to-service mTLS
-   Authorization policies
-   Traffic routing
-   Retries
-   Traffic splitting
-   Ingress/egress control
-   Standard Istio service-mesh capabilities
-   Azure monitoring integration
-   Microsoft-supported lifecycle management

The managed add-on is not simply "Istio Lite."

For standard service-mesh functionality, it provides substantial Istio
capability.

The main limitation is **deep customization and control-plane
ownership**.

------------------------------------------------------------------------

# Decision Guide

## Choose AKS Managed Istio when

-   You have a single AKS cluster or relatively simple topology.
-   You need standard Istio sidecar functionality.
-   You need mTLS and authorization.
-   You need routing, retries, and traffic splitting.
-   You need standard ingress and egress functionality.
-   You want Azure-managed upgrades and lifecycle.
-   You want Microsoft support.
-   You do not need deep customization of Istio internals.

## Choose Self-Managed Istio when

-   Multi-cluster mesh is important.
-   Ambient mode is important.
-   You need `IstioOperator`.
-   You need advanced `ProxyConfig`.
-   You need `WorkloadEntry` or `WorkloadGroup`.
-   You need custom Wasm extensions.
-   You require a specific upstream Istio version.
-   You heavily depend on `EnvoyFilter`.
-   You need advanced Envoy/Istio customization.
-   You need capabilities before they are exposed through the AKS
    add-on.

------------------------------------------------------------------------

# Recommended Evaluation Criteria

For an enterprise AKS platform, evaluate these areas first:

1.  **Multi-cluster requirements**
2.  **Gateway API requirements**
3.  **Need for custom Istio configuration**
4.  **Need for EnvoyFilter/Wasm extensions**
5.  **Istio version control**
6.  **Operational ownership**
7.  **Microsoft support requirements**
8.  **Future requirement for Ambient mode**

A useful decision matrix is:

``` text
                    Managed Istio       Self-Managed Istio
----------------------------------------------------------------
Operational effort       Low                    High
Azure integration        High                   Medium
Configuration control    Medium/Low             High
Version control          Medium/Low             High
Advanced customization   Limited                High
Multi-cluster            Limited                High
Ambient                  Limited                High
Microsoft support        High                   Customer-owned
```

## Bottom line

For most standard AKS service-mesh deployments:

> **Start with AKS Managed Istio.**

Move toward self-managed Istio when your requirements depend on
capabilities that the AKS add-on intentionally restricts, especially:

> **multi-cluster + Ambient + advanced customization + full version
> control.**

## Microsoft references

-   AKS Istio add-on overview:
    https://learn.microsoft.com/en-us/azure/aks/istio-about
-   AKS Istio support policy:
    https://learn.microsoft.com/en-us/azure/aks/istio-support-policy
