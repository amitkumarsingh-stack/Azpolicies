# Grafana Deployment Guide

This document outlines the end-to-end process for deploying Grafana with Azure Managed Prometheus integration.

## Deployment Flow
```mermaid
flowchart TD
    subgraph S1["Step 1 — Managed Identity & RBAC · akscp-infra-pipeline / akscp-aks-build"]
        A[Stage: deploy_umi_grafana\nCreates Managed Identity]
        B[Stage: deploy_rbac\nRole-based access on Prometheus]
    end
    S1 --> S2["Step 2 — SSL Certificates\nakscp-infra-foundation-templates / infra-g3-certificate-pipeline"]
    S2 --> S3["Step 3 — Register DNS\nServiceNow Portal"]
    S3 --> S4["Step 4 — Grafana App Registration\nakcp-infra-pipeline / Grafana-app-registration"]
    S4 --> S5["Step 5 — Deploy Grafana on Central Cluster\nakscp-monitoring-setup / akscp-aks-build"]
    S5 --> S6["Step 6 — Network Policies\nakscp-network-setup / Pipeline: TBD"]

    classDef purple fill:#EEEDFE,stroke:#534AB7,color:#3C3489
    classDef teal   fill:#E1F5EE,stroke:#0F6E56,color:#085041
    classDef amber  fill:#FAEEDA,stroke:#854F0B,color:#633806
    classDef blue   fill:#E6F1FB,stroke:#185FA5,color:#0C447C
    classDef coral  fill:#FAECE7,stroke:#993C1D,color:#712B13

    class A,B purple
    class S2,S5 teal
    class S3 amber
    class S4 blue
    class S6 coral
```
## Steps

### Step 1 — Managed Identity & RBAC
- **Repo:** `akscp-infra-pipeline`
- **Pipeline:** `akscp-aks-build`
- **Stages:**
  - `deploy_umi_grafana` — Creates the Managed Identity
  - `deploy_rbac` — Grants role-based access on Prometheus

### Step 2 — SSL Certificates
- **Repo:** `akscp-infra-foundation-templates`
- **Pipeline:** `infra-g3-certificate-pipeline`

### Step 3 — Register DNS
- **Portal:** ServiceNow

### Step 4 — Grafana App Registration
- **Repo:** `akcp-infra-pipeline`
- **Pipeline:** `Grafana-app-registration`

### Step 5 — Deploy Grafana on Central Cluster
- **Repo:** `akscp-monitoring-setup`
- **Pipeline:** `akscp-aks-build`

### Step 6 — Network Policies
- **Repo:** `akscp-network-setup`
- **Pipeline:** TBD
````
