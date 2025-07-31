## Benefits of AKS Managed Prometheus
1. #### 🚀 Fully Managed Service
No need to install, configure, or maintain Prometheus servers.

Microsoft handles scalability, updates, storage, and availability.

2. #### 🔄 Automatic Metric Collection
Automatically scrapes Kubernetes control plane and workload metrics.

Built-in support for Kubernetes metrics, cAdvisor, Kube-state-metrics, and custom metrics.

3. #### 💡 Native Azure Integration
Integrated with Azure Monitor, Log Analytics, and Grafana.

Seamless access to metrics across Azure resources in one place.

4. #### 📈 Scalability & Retention
Handles high-scale environments without Prometheus performance tuning.

Metric retention aligned with Azure Monitor (default is 93 days).

5. #### 🔐 Security & Compliance
Metrics are secured within Azure Monitor infrastructure.

## Reference Diagram
![alt text](image.png)
*Overview about Prometheus scraping in Azure Monitor*

## Enabling Managed Prometheus
#### Using Bicep
Below is the sample Bicep code to enable prometheus

<span style="color: green; font-family: monospace;">kubectl get pods</span>

#### Using Terraform
```
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "myAKSCluster"
  location            = azurerm_resource_group.aks_rg.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = "myaksdns"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
  }

  identity {
    type = "SystemAssigned"
  }

  azure_policy_enabled = true

  monitor_metrics {
    annotations_allowed = null
    labels_allowed = null
  }
  ```
Below highlighted code enables Promotheus on AKS

## Limitations & Known Issues

## References & Links

