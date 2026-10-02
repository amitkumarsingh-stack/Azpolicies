# AKS Grafana Dashboards – Setup Summary

What needs to be done **on each of the 3 AKS clusters** to get all dashboards fully working.

**Already working on defaults (no action needed):** Core Kubernetes, Cluster Health, Namespace Performance.

---

## 1. Enable control plane metrics (API Server dashboard)

```bash
az aks update -n <cluster> -g <resource-group> --enable-control-plane-metrics
```

- Can also be set via Bicep / ARM / Terraform if the cluster is managed that way.
- If the argument isn't recognised: add or update the `aks-preview` extension.
- If it reports a feature flag: register `AzureMonitorMetricsControlPlanePreview`.

> **Stopgap if this can't be enabled yet:** set `apiserver = true` under `cluster-metrics` in step 2.
> Rates will be approximate and the etcd panels will stay empty.

---

## 2. Create `ama-metrics-settings-configmap` in `kube-system` (CoreDNS dashboard + extra metrics)

1. Download the template: <https://raw.githubusercontent.com/Azure/prometheus-collector/main/otelcollector/configmaps/ama-metrics-settings-configmap.yaml>
2. Under `cluster-metrics`:
   - set `coredns = true`
   - set unused targets to `false` (kubeproxy, windows, network observability, dcgm, etc.) to control cost
3. Keep `minimal-ingestion-profile` → `enabled = true`.
4. Under `controlplane-metrics`, leave `apiserver = true` and `etcd = true`.
5. Apply it:

```bash
kubectl apply -f ama-metrics-settings-configmap.yaml
```

---

## 3. Verify in Grafana Explore

Wait 10–15 minutes after each change, then run:

```promql
count by (cluster) (apiserver_request_total)   # API Server
count by (cluster) (coredns_build_info)        # CoreDNS
```

---

## 4. Fill gaps only where panels show "No data"

Add the missing metric names to the matching keep-list in the configmap, separated by `|`.

| Dashboard | Panel(s) | Add to keep-list |
|---|---|---|
| Pods | Availability | `kubestate`: `kube_pod_status_ready` |
| Workloads | Progress Deadline, Rollout Stuck, Up-to-date / Misscheduled | `kubestate`: `kube_deployment_status_condition`, `kube_deployment_status_replicas_updated`, `kube_statefulset_status_replicas_updated`, `kube_daemonset_status_updated_number_scheduled`, `kube_daemonset_status_number_misscheduled` |
| Persistent Volumes | PV table, Pods With PVCs Not Running | `kubestate`: `kube_persistentvolume_info`, `kube_persistentvolume_capacity_bytes`, `kube_persistentvolume_claim_ref`, `kube_pod_spec_volumes_persistentvolumeclaims_info` |
| API Server | Latency / etcd panels | `apiserver` (controlplane): `apiserver_request_duration_seconds_*`, `etcd_request_duration_seconds_*`; `etcd`: `etcd_disk_wal_fsync_duration_seconds_bucket`, `etcd_disk_backend_commit_duration_seconds_bucket`, `etcd_mvcc_db_total_size_in_bytes`, `etcd_mvcc_db_total_size_in_use_in_bytes`, `etcd_server_leader_changes_seen_total`, `etcd_server_slow_apply_total`, `etcd_server_heartbeat_send_failures_total` |

- For histograms, include the `_bucket`, `_sum` and `_count` series.
- Only add what's actually missing – each extra series adds ingestion cost.
- To see which metrics already exist:

```promql
count by (__name__) ({__name__=~"apiserver_.*|etcd_.*|coredns_.*"})
```
