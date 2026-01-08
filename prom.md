+--------------------+
|   AKS Cluster     |
| (Prometheus data) |
+---------+----------+
          |
          | Metrics scraped & forwarded
          v
+---------------------------+
| Data Collection Rule     |
| (prom-dce-aks04)         |
+-----------+---------------+
            |
            | Uses
            v
+---------------------------+
| Data Collection Endpoint |
| (prom-dce-aks04)         |
+-----------+---------------+
            |
            | Private ingestion via AMPLS
            v
+---------------------------+
| Azure Monitor Private    |
| Link Scope (AMPLS)       |
| (PrivateOnly)            |
+-----------+---------------+
            |
            | Private Link
            v
+---------------------------+
| Private Endpoint         |
| (prometheusMetrics)      |
+-----------+---------------+
            |
            | Private traffic
            v
+---------------------------+
| Azure Monitor Workspace  |
| (prom-d-aks04)           |
+---------------------------+
