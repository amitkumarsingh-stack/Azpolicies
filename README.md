# Grafana Helm Chart – Configuration Reference

> Grafana `v12.2.0` deployed on AKS via Helm, authenticated with Azure AD, secrets managed through Azure Key Vault CSI, and exposed via Gateway API (Traefik).

---

## Table of Contents

- [Overview](#overview)
- [Image Configuration](#image-configuration)
- [Identity & RBAC](#identity--rbac)
- [Authentication](#authentication)
- [TLS & Secrets Management](#tls--secrets-management)
- [Networking & Ingress](#networking--ingress)
- [Storage](#storage)
- [Datasources](#datasources)
- [Dashboards](#dashboards)
- [Security Context](#security-context)
- [Deployment & Availability](#deployment--availability)
- [Sidecars](#sidecars)

---

## Overview

| Parameter | Value |
|---|---|
| Grafana Version | `12.2.0` |
| Namespace | `monitoring` |
| Cluster | `akscp-we-d` (AKS, West Europe) |
| Hostname | `grafana-akscp-we-d.nl.eu.abnamro.com` |
| Registry | `p-nexus-3.development.nl.eu.abnamro.com:18443` |
| Azure Tenant ID | `3a15904d-3fd9-4256-a753-beb05cdf0c6d` |

---

## Image Configuration

| Parameter | Value |
|---|---|
| Registry | `p-nexus-3.development.nl.eu.abnamro.com:18443` |
| Repository | `aec/grafana/grafana` |
| Tag | `12.2.0` |
| Pull Policy | `IfNotPresent` |
| Digest (sha) | *(not set)* |

---

## Identity & RBAC

| Parameter | Value |
|---|---|
| ServiceAccount Name | `grafana` |
| RBAC Enabled | `true` |
| RBAC Scope | Cluster-wide (`namespaced: false`) |
| Workload Identity Client ID | `cf735f27-a2e7-4dd2-b73c-dbf6649960bc` |
| PSP Enabled | `false` |
| Automount SA Token | `true` |
| Pod Label | `azure.workload.identity/use: "true"` |

---

## Authentication

### Azure AD (Primary)

| Parameter | Value |
|---|---|
| Provider | Azure AD (Entra ID) OAuth |
| Azure Auth Enabled | `true` |
| Auto Login | `false` |
| Allow Sign-Up | `true` |
| Local Admin Login | Enabled (`disable_login_form: false`) |
| Tenant ID | `3a15904d-3fd9-4256-a753-beb05cdf0c6d` |
| Allowed Organizations | `3a15904d-3fd9-4256-a753-beb05cdf0c6d` |
| Scopes | `openid email profile` |
| Auth URL | `https://login.microsoftonline.com/<tenant>/oauth2/v2.0/authorize` |
| Token URL | `https://login.microsoftonline.com/<tenant>/oauth2/v2.0/token` |

### Admin Credentials

| Parameter | Value |
|---|---|
| Existing Secret | `grafana-admin-credentials` |
| User Key | `admin-user` |
| Password Key | `admin-password` |
| Client ID Source | `$__file{/mnt/secrets-store/grafana-client-id}` |
| Client Secret Source | `$__file{/mnt/secrets-store/akscp-d-grafana}` |

---

## TLS & Secrets Management

| Parameter | Value |
|---|---|
| Secret Driver | Azure Key Vault CSI (`secrets-store.csi.k8s.io`) |
| SecretProviderClass | `azure-keyvault-user-msi` |
| Key Vault Name | `akscp01-we-d-kv` |
| UMI Client ID | `fbcf15d2-871a-43e1-a92a-8977b4dd1d31` |
| Tenant ID | `3a15904d-3fd9-4256-a753-beb05cdf0c6d` |
| Cloud | `AzurePublicCloud` |
| Secrets Mount Path | `/mnt/secrets-store` |
| TLS Cert Path | `/run/secrets/vault.azure.com/ingress-tls-certs/tls.crt` |
| TLS Key Path | `/run/secrets/vault.azure.com/ingress-tls-certs/tls.key` |

### Secrets Pulled from AKV

| Secret Name | Type | Purpose |
|---|---|---|
| `ingress-tls-certs` | `kubernetes.io/tls` | TLS certificate & key for HTTPS |
| `grafana-client-id` | `Opaque` | Azure AD OAuth client ID |
| `akscp-d-grafana` | `Opaque` | Azure AD OAuth client secret |

---

## Networking & Ingress

### Service

| Parameter | Value |
|---|---|
| Service Type | `ClusterIP` |
| Service Port | `80` |
| Container Port | `3000` |
| Ingress (classic) | `false` |

### Gateway API (HTTPRoute)

| Parameter | Value |
|---|---|
| Enabled | `true` |
| API Version | `gateway.networking.k8s.io/v1` |
| Kind | `HTTPRoute` |
| Gateway Name | `shared-gateway` |
| Gateway Namespace | `traefik` |
| Hostname | `grafana-akscp-we-d.nl.eu.abnamro.com` |
| Path Match | `PathPrefix: /` |
| Backend Service | `grafana:80` in `monitoring` namespace |
| Root URL | `https://grafana-akscp-we-d.nl.eu.abnamro.com` |

---

## Storage

| Parameter | Value |
|---|---|
| Persistence Enabled | `true` |
| Type | `PVC` |
| Size | `10Gi` |
| Access Mode | `ReadWriteOnce` |
| Finalizer | `kubernetes.io/pvc-protection` |
| In-Memory Fallback | `false` |
| initChownData | `false` |

---

## Datasources

| Name | Type | Default | Auth |
|---|---|---|---|
| Azure Monitor | `grafana-azure-monitor-datasource` | ✅ Yes | Workload Identity |
| Azure Monitor Workspace (Prometheus) | `prometheus` | ❌ No | Workload Identity |

### Azure Monitor

| Parameter | Value |
|---|---|
| Auth Type | `workloadidentity` |
| Subscription ID | `9c9f0147-d033-4f78-a2c5-f3deb850c554` |
| Editable | `true` |

### Prometheus (Azure Managed)

| Parameter | Value |
|---|---|
| URL | `https://akscp01-we-d-prom-endmhca9end6a0gr.westeurope.prometheus.monitor.azure.com` |
| Cloud | `AzureCloud` |
| Auth Type | `workloadidentity` |
| Editable | `true` |

---

## Dashboards

| Provider Name | Folder | ConfigMap | Deletion Protected |
|---|---|---|---|
| `default` | *(root)* | `default-dashboards` | `false` |
| `cilium` | `Cilium` | `cilium-dashboards` | `false` |
| `cluster` | `cluster` | `cluster-dashboards` | `false` |

> Dashboards are loaded statically from ConfigMaps. Dynamic sidecar loading is disabled.

---

## Security Context

### Pod-level

| Parameter | Value |
|---|---|
| Run As Non-Root | `true` |
| Run As User | `472` |
| Run As Group | `472` |
| FS Group | `472` |

### Container-level

| Parameter | Value |
|---|---|
| Allow Privilege Escalation | `false` |
| Capabilities | Drop `ALL` |
| Seccomp Profile | `RuntimeDefault` |

---

## Deployment & Availability

| Parameter | Value |
|---|---|
| Replicas | `1` |
| Deployment Strategy | `RollingUpdate` |
| Autoscaling | `false` |
| PodDisruptionBudget | Not configured |
| Revision History Limit | `10` |
| Scheduler | default |
| Toleration | `CriticalAddonsOnly: Exists` |
| Liveness Probe Path | `GET /api/health:3000` |
| Readiness Probe Path | `GET /api/health:3000` |
| Liveness Initial Delay | `60s` |
| Liveness Timeout | `30s` |
| Liveness Failure Threshold | `10` |

---

## Sidecars

| Sidecar | Enabled | Notes |
|---|---|---|
| Dashboards | `false` | Managed via static ConfigMaps |
| Datasources | `false` | Managed via static `values.yaml` |
| Alerts | `false` | — |
| Plugins | `false` | — |
| Notifiers | `false` | — |

> All sidecars use image `quay.io/kiwigrid/k8s-sidecar:1.30.10` when enabled.

---

## Notes

- **No public images**: All images are mirrored to the internal Nexus registry. Update mirror references when upgrading chart versions.
- **Secret rotation**: Rotating AKV secrets does not require pod restarts — the CSI driver handles live updates.
- **Local admin**: `disable_login_form` is set to `false` to retain break-glass admin access. Set to `true` to enforce Azure AD-only login.
- **Workload Identity**: Both the ServiceAccount annotation (`azure.workload.identity/client-id`) and pod label (`azure.workload.identity/use: "true"`) are required for WI to function correctly.
