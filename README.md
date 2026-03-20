flowchart TD
    DEV["👤 Developer — git push"]

    DEV --> S1

    subgraph S1["⚙️ Step 1 — Managed Identity & RBAC · akscp-infra-pipeline / akscp-aks-build"]
        A["🔐 Stage: deploy_umi_grafana\nCreates Managed Identity"]
        B["🛡️ Stage: deploy_rbac\nRole-based access on Prometheus"]
    end

    S1 --> S2["🔒 Step 2 — SSL Certificates\nakscp-infra-foundation-templates / infra-g3-certificate-pipeline"]
    S2 --> S3["🌐 Step 3 — Register DNS\nServiceNow Portal"]
    S3 --> S4["📋 Step 4 — Grafana App Registration\nakcp-infra-pipeline / Grafana-app-registration"]
    S4 --> S5["🚀 Step 5 — Deploy Grafana on Central Cluster\nakscp-monitoring-setup / akscp-aks-build"]
    S5 --> S6["🔗 Step 6 — Network Policies\nakscp-network-setup / Pipeline: TBD"]

    classDef dev    fill:#0d1117,stroke:#30363d,color:#e6edf3
    classDef purple fill:#3d1f7a,stroke:#7c4dff,color:#e0d7ff
    classDef teal   fill:#0d3b2e,stroke:#00c896,color:#b3f5e0
    classDef amber  fill:#3b2500,stroke:#f0a500,color:#ffe4a0
    classDef blue   fill:#0c2340,stroke:#388bfd,color:#c8e1ff
    classDef coral  fill:#3b0d0d,stroke:#f85149,color:#ffc1c1

    class DEV dev
    class A,B purple
    class S2,S5 teal
    class S3 amber
    class S4 blue
    class S6 coral
