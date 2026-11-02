# Crossplane on AKS: Managing Kubernetes Resources Across Clusters

This guide sets up **Crossplane on one AKS cluster** (`aks01`) so it can create and manage Kubernetes resources on **other AKS clusters** (`aks02`, `aks03`).

There are two ways for Crossplane to authenticate to the target clusters:

| Option | How it authenticates | Use for |
|---|---|---|
| **A. Azure Workload Identity** (recommended) | A managed identity federated with the provider's ServiceAccount. No stored tokens. | Production |
| **B. ServiceAccount token** | A long-lived token in a kubeconfig Secret | Quick PoC, or clusters without Entra ID |

---

## Contents

1. [Architecture](#1-architecture)
2. [Prerequisites](#2-prerequisites)
3. [Infrastructure with Terraform](#3-infrastructure-with-terraform)
4. [Verify connectivity between clusters](#4-verify-connectivity-between-clusters)
5. [Install Crossplane and provider-kubernetes](#5-install-crossplane-and-provider-kubernetes)
6. [Option A: Workload Identity (recommended)](#6-option-a-workload-identity-recommended)
7. [Option B: ServiceAccount token](#7-option-b-serviceaccount-token)
8. [Creating resources on target clusters](#8-creating-resources-on-target-clusters)
9. [Object reference](#9-object-reference)
10. [Optional: Helm charts with provider-helm](#10-optional-helm-charts-with-provider-helm)
11. [Troubleshooting](#11-troubleshooting)
12. [Before production](#12-before-production)
13. [References](#13-references)

---

## 1. Architecture

```
rg-aksplatform
└── vnet-aksplatform (10.30.0.0/16)
    ├── snet-aks01 (10.30.0.0/22) + nsg-aks01 ──▶ private AKS aks01  ← Crossplane runs here
    ├── snet-aks02 (10.30.4.0/22) + nsg-aks02 ──▶ private AKS aks02  ← target
    └── snet-aks03 (10.30.8.0/22) + nsg-aks03 ──▶ private AKS aks03  ← target
```

How it works:

```
aks01: provider-kubernetes pod
  │  ServiceAccount token (OIDC issuer of aks01)
  ▼
Entra ID ── federated credential ──▶ managed identity "id-crossplane"
  │  Entra access token
  ▼
aks02 / aks03 API server (TCP 443) ── Azure RBAC role ──▶ allowed
```

- You create **`Object`** resources on `aks01`. Each one wraps a normal Kubernetes manifest.
- **provider-kubernetes** creates that manifest on the target cluster named in `providerConfigRef` and keeps it in sync. Drift is corrected automatically.
- There is **one ProviderConfig per target cluster**.

---

## 2. Prerequisites

### Tools

- `az` CLI, `kubectl` (v1.24+), `helm` (v3.8+), `terraform` (v1.5+)

**Windows (Git Bash or MSYS2 UCRT64):**
- Run multi-line commands from a script file, and strip Windows line endings first: `sed -i 's/\r$//' script.sh`.
- Prefix `az` and `kubectl` commands that contain `/subscriptions/...` or `/var/run/...` with `MSYS_NO_PATHCONV=1`. Without it, the shell rewrites them into Windows paths.
- Append `| tr -d '\r'` when capturing `az` or `kubectl` output into variables.

### Access

The clusters are **private**, so run these commands from a machine that can reach the VNet: a jumphost, a peered network or a VPN. Alternatively, use `az aks command invoke`.

```bash
RG=rg-aksplatform
for C in aks01 aks02 aks03; do
  az aks get-credentials -g $RG -n $C --overwrite-existing
  kubectl --context $C get nodes
done
kubectl config get-contexts
```

> Use the **NAME** column of `get-contexts` with `--context`. The AUTHINFO column contains the resource group name, which is easy to mistake for a context name.

---

## 3. Infrastructure with Terraform

The Terraform project creates one resource group, one VNet, three subnets (each with an NSG that has only Azure's default rules) and three private AKS clusters. Files: `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `terraform.tfvars.example`.

Main settings for each cluster:
- Private API server with an AKS-managed private DNS zone linked to the shared VNet
- Azure CNI Overlay; pod and service CIDRs are reused across clusters
- Entra ID with **Azure RBAC**
- **OIDC issuer and Workload Identity enabled** (required for Option A)
- A user-assigned control-plane identity with Network Contributor on its own subnet
- Autoscaling system node pool (1 to 3 × Standard_D4s_v5)

```bash
cp terraform.tfvars.example terraform.tfvars   # set subscription_id, admin_group_object_ids
terraform init
terraform validate
terraform plan -out tfplan
terraform apply tfplan
terraform output clusters
```

> Default NSG rules allow traffic within the VNet, so the clusters can reach each other's API servers on port 443 with no extra rules. When clusters are in **different VNets**, you need VNet peering (or hub routing), a private DNS zone link to the Crossplane VNet, and NSG or firewall rules allowing TCP 443.

---

## 4. Verify connectivity between clusters

The AKS API server listens on **TCP 443**, for both public and private clusters.

```bash
kubectl --context aks01 run nettest --image=mcr.microsoft.com/azurelinux/base/core:3.0 --restart=Never -- sleep 3600
kubectl --context aks01 wait --for=condition=Ready pod/nettest --timeout=120s

for C in aks02 aks03; do
  URL=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$C\")].cluster.server}")
  echo -n "$C: "
  kubectl --context aks01 exec nettest -- curl -sk -o /dev/null -w "%{http_code}\n" --max-time 5 "$URL/version"
done

kubectl --context aks01 delete pod nettest
```

| Result | Meaning |
|---|---|
| `200` / `401` / `403` | Reachable. A 401 is expected here because the test sends no credentials. |
| `000` / timeout | Blocked: peering, NSG, firewall or UDR, or authorized IP ranges |
| `Could not resolve host` | Private DNS zone isn't linked to the source VNet |

> Use MCR images (`mcr.microsoft.com/...`) for test pods. Docker Hub may be blocked or rewritten by a registry proxy. If nodes are tainted, the test pod needs a matching toleration, and the key, value and effect must match the taint **exactly**.

---

## 5. Install Crossplane and provider-kubernetes

### 5.1 Crossplane

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

helm install crossplane crossplane-stable/crossplane \
  --kube-context aks01 -n crossplane-system --create-namespace

kubectl --context aks01 get pods -n crossplane-system
```

Both `crossplane-...` and `crossplane-rbac-manager-...` must be **Running**. The RBAC manager grants providers access to their own CRDs. If it isn't running, providers fail with `forbidden` errors.

> Small or full nodes: if the RBAC manager is `Pending` with `Insufficient cpu`, add `--set resourcesRBACManager.requests.cpu=25m`, or scale the node pool.
> Tainted nodes: add `nodeSelector` and `tolerations` for both `crossplane` and `rbacManager` through Helm `--set` values.

### 5.2 Namespace for remote resources

```bash
kubectl --context aks01 create namespace remote-apps
```

### 5.3 provider-kubernetes

**For Option A (Workload Identity),** install the provider together with the DeploymentRuntimeConfig in [section 6.4](#64-wire-the-provider-pod-to-the-identity).

**For Option B,** install it directly:

```yaml
# provider.yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:v1.0.0
```

```bash
kubectl --context aks01 apply -f provider.yaml
kubectl --context aks01 get providers.pkg.crossplane.io -w   # INSTALLED=True, HEALTHY=True
```

> **What is a DeploymentRuntimeConfig?** Crossplane creates the provider's Deployment, ServiceAccount and Service itself, so you can't edit them directly. A `DeploymentRuntimeConfig` tells Crossplane how to build them: labels, annotations, ServiceAccount name, tolerations, resources and so on. The Provider references it with `spec.runtimeConfigRef`.

---

## 6. Option A: Workload Identity (recommended)

### 6.1 Create the managed identity

```bash
RG=rg-aksplatform
az identity create -g $RG -n id-crossplane

CLIENT_ID=$(az identity show -g $RG -n id-crossplane --query clientId -o tsv | tr -d '\r')
PRINCIPAL_ID=$(az identity show -g $RG -n id-crossplane --query principalId -o tsv | tr -d '\r')
TENANT_ID=$(az account show --query tenantId -o tsv | tr -d '\r')
echo "CLIENT_ID=$CLIENT_ID PRINCIPAL_ID=$PRINCIPAL_ID TENANT_ID=$TENANT_ID"
```

> Variables don't survive a new shell. Re-run these lines if `$PRINCIPAL_ID` or `$CLIENT_ID` is empty. An empty value causes `argument --assignee-object-id: expected one argument`.

### 6.2 Federate it with the provider ServiceAccount on aks01

```bash
ISSUER=$(az aks show -g $RG -n aks01 --query oidcIssuerProfile.issuerUrl -o tsv | tr -d '\r')

az identity federated-credential create -g $RG --identity-name id-crossplane \
  --name crossplane-provider-kubernetes \
  --issuer "$ISSUER" \
  --subject system:serviceaccount:crossplane-system:provider-kubernetes \
  --audiences api://AzureADTokenExchange
```

The subject must match the ServiceAccount name exactly. Section 6.4 fixes the name to `provider-kubernetes`; by default Crossplane adds a random suffix.

### 6.3 Grant Azure RBAC on each target cluster

```bash
for C in aks02 aks03; do
  AKS_ID=$(az aks show -g $RG -n $C --query id -o tsv | tr -d '\r')
  echo "$C -> $AKS_ID"
  MSYS_NO_PATHCONV=1 az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Azure Kubernetes Service RBAC Cluster Admin" --scope "$AKS_ID"
done

MSYS_NO_PATHCONV=1 az role assignment list --assignee "$PRINCIPAL_ID" --all -o table
```

> Cluster Admin is for the PoC. For production, use `Azure Kubernetes Service RBAC Writer` or a namespace-scoped assignment. Role assignments can take a few minutes to take effect.

### 6.4 Wire the provider pod to the identity

```yaml
# provider-wi.yaml
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: provider-kubernetes-wi
spec:
  serviceAccountTemplate:
    metadata:
      name: provider-kubernetes                         # fixed name, matches the federated credential
      annotations:
        azure.workload.identity/client-id: "<CLIENT_ID>"
  deploymentTemplate:
    spec:
      selector: {}
      template:
        metadata:
          labels:
            azure.workload.identity/use: "true"         # webhook injects the Azure token and env vars
---
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-kubernetes
spec:
  package: xpkg.crossplane.io/crossplane-contrib/provider-kubernetes:v1.0.0
  runtimeConfigRef:
    name: provider-kubernetes-wi
```

```bash
sed -i "s/<CLIENT_ID>/$CLIENT_ID/" provider-wi.yaml
kubectl --context aks01 apply -f provider-wi.yaml
```

Verify:

```bash
kubectl --context aks01 get sa provider-kubernetes -n crossplane-system -o yaml | grep client-id

POD=$(kubectl --context aks01 get pod -n crossplane-system -l pkg.crossplane.io/provider=provider-kubernetes -o jsonpath='{.items[0].metadata.name}')
kubectl --context aks01 -n crossplane-system get pod $POD \
  -o jsonpath='{range .spec.containers[0].env[*]}{.name}={.value}{"\n"}{end}' | grep AZURE_
```

The output must include `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_FEDERATED_TOKEN_FILE` and `AZURE_AUTHORITY_HOST`.

### 6.5 Identity Secret (shared by all target clusters)

provider-kubernetes builds its Azure token settings **entirely from this JSON**. It does not fall back to the pod's environment variables or the kubeconfig's `--server-id`. All five fields are required:

| Field | Value |
|---|---|
| `clientId` | Client ID of `id-crossplane` |
| `tenantId` | Entra tenant ID |
| `federatedTokenFile` | Value of `AZURE_FEDERATED_TOKEN_FILE` in the pod (normally `/var/run/secrets/azure/tokens/azure-identity-token`) |
| `authorityHost` | Value of `AZURE_AUTHORITY_HOST` (normally `https://login.microsoftonline.com/`) |
| `serverId` | AKS Entra server app ID: `6dae42f8-4368-4678-94ff-3960e28e3630` for AKS-managed Entra ID. Confirm with `grep -A1 -- "--server-id"` on a user kubeconfig. |

```bash
MSYS_NO_PATHCONV=1 kubectl --context aks01 -n remote-apps create secret generic azure-wi-identity \
  --from-literal=credentials="{\"clientId\":\"$CLIENT_ID\",\"tenantId\":\"$TENANT_ID\",\"federatedTokenFile\":\"/var/run/secrets/azure/tokens/azure-identity-token\",\"authorityHost\":\"https://login.microsoftonline.com/\",\"serverId\":\"6dae42f8-4368-4678-94ff-3960e28e3630\"}"

# Check: the path must start with /var/run, not C:/
kubectl --context aks01 -n remote-apps get secret azure-wi-identity -o jsonpath='{.data.credentials}' | base64 -d; echo
```

> The Secret contains IDs only, no passwords or tokens.

### 6.6 Per target cluster: kubeconfig Secret and ProviderConfig

Repeat for each target cluster. The example uses `aks02`.

**Tokenless kubeconfig.** Use the normal user kubeconfig, **not `--admin`**:

```bash
az aks get-credentials -g $RG -n aks02 --file aks02-wi.kubeconfig --overwrite-existing
grep -E "kubelogin|server-id" aks02-wi.kubeconfig    # expect "command: kubelogin" and "--server-id"

kubectl --context aks01 -n remote-apps create secret generic aks02-wi-kubeconfig \
  --from-file=kubeconfig=aks02-wi.kubeconfig
rm aks02-wi.kubeconfig
```

> The `kubelogin is not installed...` text in the file is just the kubeconfig's `installHint`, not an error. The provider handles the Entra sign-in itself.

**ProviderConfig:**

```yaml
# providerconfig-aks02-wi.yaml
apiVersion: kubernetes.m.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: aks02
  namespace: remote-apps
spec:
  credentials:
    source: Secret
    secretRef:
      name: aks02-wi-kubeconfig
      namespace: remote-apps
      key: kubeconfig
  identity:
    type: AzureWorkloadIdentityCredentials
    source: Secret
    secretRef:
      name: azure-wi-identity          # shared Secret from 6.5
      namespace: remote-apps
      key: credentials
```

```bash
kubectl --context aks01 apply -f providerconfig-aks02-wi.yaml
kubectl --context aks01 get providerconfigs.kubernetes.m.crossplane.io -n remote-apps
```

> If `apply` says `unchanged` after you edited the file, your edit wasn't saved. Check the live value with
> `kubectl get providerconfigs.kubernetes.m.crossplane.io aks02 -n remote-apps -o yaml`.

**For aks03:** fetch aks03's kubeconfig into a Secret named `aks03-wi-kubeconfig`, and create a ProviderConfig named `aks03` that points to it. The `azure-wi-identity` Secret is reused.

Then continue with [section 8](#8-creating-resources-on-target-clusters).

---
To force immediate reconcile.
```
kubectl --context aks03 delete ns crossplane-wi-demo-aks03
kubectl --context aks01 annotate object.kubernetes.m.crossplane.io demo-ns-aks03 -n remote-apps \
  reconcile-at="$(date +%s)" --overwrite
kubectl --context aks03 get ns -w
```
---

## 7. Option B: ServiceAccount token

This option needs no Entra ID setup, but the long-lived tokens it stores must be rotated.

### 7.1 ServiceAccount on the target cluster

```yaml
# crossplane-remote-sa.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: crossplane-remote
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: crossplane-remote
  namespace: crossplane-remote
---
apiVersion: v1
kind: Secret
metadata:
  name: crossplane-remote-token
  namespace: crossplane-remote
  annotations:
    kubernetes.io/service-account.name: crossplane-remote
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: crossplane-remote-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin              # PoC only
subjects:
- kind: ServiceAccount
  name: crossplane-remote
  namespace: crossplane-remote
```

```bash
kubectl --context aks02 apply -f crossplane-remote-sa.yaml
kubectl --context aks02 -n crossplane-remote get secret crossplane-remote-token   # DATA = 3
```

### 7.2 Build the kubeconfig

Let `kubectl` build the file; hand-pasted base64 breaks easily on Windows. Save this as `build-kubeconfig.sh`:

```bash
#!/bin/bash
set -e
C=${1:?usage: build-kubeconfig.sh <context>}
rm -f $C-config.yaml $C-ca.crt

kubectl --context $C -n crossplane-remote get secret crossplane-remote-token \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > $C-ca.crt
TOKEN=$(kubectl --context $C -n crossplane-remote get secret crossplane-remote-token \
  -o jsonpath='{.data.token}' | base64 -d | tr -d '\r')
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$C\")].cluster.server}" | tr -d '\r')

echo "SERVER=$SERVER"; echo "TOKEN length=${#TOKEN}"; head -1 $C-ca.crt

kubectl --kubeconfig=$C-config.yaml config set-cluster $C --server="$SERVER" \
  --certificate-authority=$C-ca.crt --embed-certs=true
kubectl --kubeconfig=$C-config.yaml config set-credentials crossplane-remote --token="$TOKEN"
kubectl --kubeconfig=$C-config.yaml config set-context $C --cluster=$C --user=crossplane-remote
kubectl --kubeconfig=$C-config.yaml config use-context $C

echo "--- Testing ---"
kubectl --kubeconfig $C-config.yaml get ns
```

```bash
sed -i 's/\r$//' build-kubeconfig.sh
bash build-kubeconfig.sh aks02
```

> A kubeconfig (`kind: Config`) is a credentials file. Don't `kubectl apply` it; that fails with `no matches for kind "Config"`. Also don't combine `--context` with `--kubeconfig` when testing the file.

### 7.3 Secret and ProviderConfig

```bash
kubectl --context aks01 -n remote-apps create secret generic aks02-kubeconfig \
  --from-file=kubeconfig=aks02-config.yaml
rm aks02-ca.crt aks02-config.yaml
```

```yaml
apiVersion: kubernetes.m.crossplane.io/v1alpha1
kind: ProviderConfig
metadata:
  name: aks02
  namespace: remote-apps
spec:
  credentials:
    source: Secret
    secretRef:
      name: aks02-kubeconfig
      namespace: remote-apps      # required in this provider version
      key: kubeconfig
```

---

## 8. Creating resources on target clusters

```yaml
# test-aks02.yaml
apiVersion: kubernetes.m.crossplane.io/v1alpha1
kind: Object
metadata:
  name: demo-ns-aks02
  namespace: remote-apps
spec:
  providerConfigRef:
    kind: ProviderConfig
    name: aks02                    # ← selects the target cluster
  forProvider:
    manifest:
      apiVersion: v1
      kind: Namespace
      metadata:
        name: crossplane-demo
```

```bash
kubectl --context aks01 apply -f test-aks02.yaml

# On aks01: SYNCED=True and READY=True
kubectl --context aks01 get objects.kubernetes.m.crossplane.io -n remote-apps

# On the target, look for the name inside the manifest, not the Object name
kubectl --context aks02 get ns crossplane-demo
```

Drift test: delete the resource on the target. It comes back within about a minute.

```bash
kubectl --context aks02 delete ns crossplane-demo
kubectl --context aks02 get ns crossplane-demo -w
```

If `SYNCED=False`, check the reason:

```bash
kubectl --context aks01 describe object.kubernetes.m.crossplane.io demo-ns-aks02 -n remote-apps | sed -n '/Conditions:/,$p'
kubectl --context aks01 logs -n crossplane-system -l pkg.crossplane.io/provider=provider-kubernetes --tail=30
```

> Always pass `--context`. Without it, `kubectl` uses your current context, which may not be the cluster you mean.

### Deploying the same resource to several clusters

- **Shell loop:** template the YAML with `sed "s/__CLUSTER__/$C/g"` and apply it once per cluster.
- **Kustomize:** use one base plus an overlay per cluster that patches `providerConfigRef.name`.
- **Composition (recommended next step):** an XRD such as `TeamNamespace` with `spec.clusters: [aks02, aks03]`. A Composition (function-go-templating) creates one Object per listed cluster.

---

## 9. Object reference

See exactly what your installed version supports:

```bash
kubectl --context aks01 explain objects.kubernetes.m.crossplane.io.spec --recursive
kubectl --context aks01 explain providerconfigs.kubernetes.m.crossplane.io.spec --recursive
```

| Field | Purpose |
|---|---|
| `forProvider.manifest` | Kubernetes resource to create on the target (required) |
| `providerConfigRef` | Target cluster (`kind: ProviderConfig`, `name: <cluster>`) |
| `managementPolicies` | How much control Crossplane has (see below) |
| `readiness.policy` | `SuccessfulCreate` (default), `DeriveFromObject`, `AllTrue`, `DeriveFromCelQuery` + `celQuery` |
| `references` | `dependsOn` for ordering; `patchesFrom` + `toFieldPath` to copy values from another remote resource |
| `connectionDetails` + `writeConnectionSecretToRef` | Copy values from remote resources into a Secret in the Object's namespace |
| `watch` | `true` reacts to changes on the target immediately instead of on periodic resync |

### Management policies

| Policy | What Crossplane does |
|---|---|
| `*` | Everything (default) |
| `Observe` | Read and report state |
| `Create` | Create if missing |
| `Update` | Update when the spec changes |
| `Delete` | Delete on the target when the Object is deleted |
| `LateInitialize` | Fill unset spec fields from the live resource |

Management policies are set on each Object, in spec.managementPolicies. They aren’t set on the Provider or the ProviderConfig, so each Object can have its own.

If you leave it out, the default is ["*"] (full control, including delete).

Sample manifest for **Create**
```
apiVersion: kubernetes.m.crossplane.io/v1alpha1
kind: Object
metadata:
  name: observe-coredns-aks02
  namespace: remote-apps
spec:
  managementPolicies: ["Create"]     # Create if missing
  providerConfigRef:
    kind: ProviderConfig
    name: aks02
  forProvider:
    manifest:                         # only enough to identify the resource
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: coredns
        namespace: kube-system
```

Common combinations:
- `["*"]`: full management.
- `["Observe"]`: read-only; adopt or monitor an existing resource.
- `["Observe","Create","Update","LateInitialize"]`: keep the resource on the target when the Object is deleted. This replaces `deletionPolicy: Orphan`, which doesn't exist on Crossplane v2 namespaced resources.

---

## 10. Optional: Helm charts with provider-helm

Not yet tested in the PoC. provider-helm installs Helm charts on target clusters and can reuse the same kubeconfig and identity Secrets.

```yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-helm
spec:
  package: xpkg.crossplane.io/crossplane-contrib/provider-helm:v1.0.0
---
apiVersion: helm.m.crossplane.io/v1beta1
kind: Release
metadata:
  name: podinfo
  namespace: remote-apps
spec:
  providerConfigRef:
    kind: ProviderConfig
    name: aks02
  forProvider:
    chart:
      name: podinfo
      repository: https://stefanprodan.github.io/podinfo
      version: 6.7.1
    namespace: podinfo
    values:
      replicaCount: 2
```

You also need a `helm.m.crossplane.io/v1beta1` ProviderConfig for each cluster. For Workload Identity, give provider-helm its own DeploymentRuntimeConfig and add a federated credential for its ServiceAccount.

**Local charts:** the provider can't read files from your machine. Push the chart to ACR as an OCI artifact and reference it from the Release:

```bash
helm package ./mychart
TOKEN=$(az acr login --name <acr> --expose-token --query accessToken -o tsv)
helm registry login <acr>.azurecr.io --username 00000000-0000-0000-0000-000000000000 --password "$TOKEN"
helm push mychart-0.1.0.tgz oci://<acr>.azurecr.io/helm
```

Then set `chart.repository: oci://<acr>.azurecr.io/helm` and a `pullSecretRef` pointing to a pull-only ACR token.

---

## 11. Troubleshooting

### Networking and scheduling

| Symptom | Cause | Fix |
|---|---|---|
| Pod Pending: `untolerated taint(s)` | Nodes are tainted, or the toleration value doesn't match (e.g. `sharedpool` vs `shared`) | Match the taint key, value and effect exactly |
| `kubectl run`: timed out waiting for the condition | The pod never started (image pull or scheduling) | `kubectl describe pod`; use MCR images; delete the leftover pod |
| `unknown flag --nc` | No standalone `--` before the container command | Use `kubectl run ... -- nc ...` with a space on both sides of `--` |
| curl times out to a private IP | No network path between the VNets | Peering or hub routing, plus NSG and firewall rules for TCP 443 |
| `Could not resolve host` | Private DNS zone isn't linked | Link the target's private DNS zone to the source VNet |

### Crossplane and provider

| Symptom | Cause | Fix |
|---|---|---|
| Provider logs: `forbidden ... cannot list objects` | RBAC manager isn't running | Fix the RBAC manager (taints or CPU), then restart the provider pod |
| RBAC manager Pending: `Insufficient cpu` | Node full, autoscaler at its maximum | `--set resourcesRBACManager.requests.cpu=25m`, or scale the node pool |
| `ProviderConfig "<name>" not found` | ProviderConfig not applied, or in the wrong namespace or cluster | Apply it with `--context aks01` in the Object's namespace |
| `secretRef.namespace: Required value` | Required by this provider version | Add `namespace` under `secretRef` |
| Objects synced but not visible on the target | Wrong context or wrong name | Use `--context <target>` and the manifest's name |

### Kubeconfig (Option B)

| Symptom | Cause | Fix |
|---|---|---|
| `no matches for kind "Config"` | You ran `kubectl apply` on a kubeconfig | Store the kubeconfig in a Secret |
| `illegal base64 data at input byte 0` | Hand-built file broken (empty variable or CRLF line endings) | Use `build-kubeconfig.sh` |

### Workload Identity (Option A)

| Error message | Cause | Fix |
|---|---|---|
| `argument --assignee-object-id: expected one argument` | `$PRINCIPAL_ID` empty (new shell) | Re-set the variables (6.1) |
| Role assignment scope looks like `C:/...` | MSYS path conversion | Prefix the command with `MSYS_NO_PATHCONV=1` |
| `unexpected end of JSON input` | `identity.source: None`; this provider requires the JSON Secret | Use `source: Secret` with `azure-wi-identity` |
| `federated token file has to be provided` | JSON is missing `federatedTokenFile` (and `authorityHost`) | Add all five fields (6.5) |
| `Secret "<name>" not found` | Wrong `identity.secretRef.name` | Correct the name, re-apply, and confirm it says `configured` |
| `serverID cannot be empty` | JSON is missing `serverId` | Add `"serverId":"6dae42f8-4368-4678-94ff-3960e28e3630"` |
| `AADSTS70021` / no matching federated identity | Federated credential subject or issuer mismatch | Subject must be `system:serviceaccount:crossplane-system:provider-kubernetes`, and issuer must be aks01's OIDC URL |
| `forbidden` / `User "<guid>" cannot ...` | Azure RBAC role missing or not yet propagated | Check role assignments on the target and wait a few minutes |
| Missing exec provider / server-id | `--admin` kubeconfig used | Re-fetch with `az aks get-credentials` without `--admin` |

After changing a Secret, restart the provider so it picks up the new value:

```bash
kubectl --context aks01 delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-kubernetes
```

---

## 12. Before production

- **Least privilege:** replace Cluster Admin (Azure RBAC) or `cluster-admin` (Kubernetes RBAC) with roles scoped to the namespaces and kinds Crossplane manages.
- **Prefer Workload Identity:** remove Option B ServiceAccounts, token Secrets and ClusterRoleBindings from targets once Option A works.
- **Capacity:** size the Crossplane cluster for the providers and number of Objects you plan to run.
- **Registry:** confirm that `xpkg.crossplane.io` package pulls work through any corporate proxy, or mirror the packages.
- **GitOps:** keep Objects, ProviderConfigs and DeploymentRuntimeConfigs in Git (Kustomize overlays per environment).
- **ClusterProviderConfig:** if teams create Objects in their own namespaces, use one `ClusterProviderConfig` per target cluster instead of namespaced ProviderConfigs.
- **Next step:** build a Composition (for example `TeamNamespace`) to offer namespace-as-a-service across clusters.
- **Cleanup:** delete test pods, test Objects and any local kubeconfig or CA files.

---

## 13. References

- provider-kubernetes: https://github.com/crossplane-contrib/provider-kubernetes
- provider-kubernetes API docs: https://marketplace.upbound.io/providers/crossplane-contrib/provider-kubernetes
- provider-helm Release API: https://marketplace.upbound.io/providers/upbound/provider-helm/v1.4.0/resources/helm.m.crossplane.io/Release/v1beta1
- Crossplane documentation: https://docs.crossplane.io
- AKS Workload Identity: https://learn.microsoft.com/en-us/azure/aks/workload-identity-deploy-cluster
