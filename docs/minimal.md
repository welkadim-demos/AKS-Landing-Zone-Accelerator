# Minimal hub

[Overview](../README.md) | [Scenarios](./scenarios.md) | [Deployment guide](./deployment.md)

This scenario deploys a peered hub and spoke in Sweden Central, two storage
accounts and private AKS, without ingress, a firewall or databases.

## Parameters and resources

Leave `$environment = 'minimal'` in [deployment.azcli](../deployment.azcli).
It selects these parameter files:

| Stage | Parameters |
| --- | --- |
| Monitoring (optional) | [main.bicepparam](../environments/minimal/02-0-Monitoring/main.bicepparam) |
| Hub | [main.bicepparam](../environments/minimal/02-Network-Hub/main.bicepparam) |
| DNS zones | [main.bicepparam](../environments/minimal/03-0-DNSZones/main.bicepparam) |
| Spoke | [main.bicepparam](../environments/minimal/03-Network-LZ/main.bicepparam) |
| DNS links | [links.bicepparam](../environments/minimal/03-0-DNSZones/links.bicepparam) |
| Supporting | [main.bicepparam](../environments/minimal/04-AKS-Supporting/main.bicepparam) |
| AKS | [main.bicepparam](../environments/minimal/05-AKS/main.bicepparam) |

This profile creates:

- One hub VNet with one ordinary subnet, no Firewall, Bastion or VM route table.
- A peered spoke with AKS and private-endpoint subnets, without Application Gateway,
  its public IP, NSG or route table. Every subnet has an NSG and no default outbound access.
- Three private DNS zones linked to the spoke: regional AKS plus `blob` and `file`
  storage. The other storage services are optional: `dfs` (hierarchical namespace),
  `queue` and `table` can be added by listing them in `storageServices` (DNS zone and
  link stages) and `storagePrivateEndpointServices` (supporting stage). Static website
  (`web`) endpoints are not supported. ACR and Key Vault
  zones are skipped because those services are off (`deployACRZone`,
  `deployKeyVaultZone`, `linkACRZone`, `linkKeyVaultZone`). Database zones and
  database resources are not deployed.
- Exactly two zone-redundant (`Standard_ZRS`) `StorageV2` accounts, each with two private endpoints (`blob`, `file`) and public
  network access disabled. The accounts share DNS zones. Creating a private
  endpoint does not enable optional account features such as hierarchical
  namespace.
- An AKS managed identity, Log Analytics workspace, and private AKS with three
  node pools and Standard Load Balancer outbound traffic: `base` (system and
  application), `burst` (Spot, for jobs) and `burstmemory` (memory-optimised, temporary).
  Both burst pools are tainted so only workloads that tolerate them schedule there.
  Both ingress add-ons, ACR integration and Key Vault integration are off.

See the [deployment guide](./deployment.md#security-and-operations) for shared
security, policy and diagnostic settings.

## Design choices and limits

Deliberate minimal choices that are not best practice for production: Premium/LTS tier,
a system pool that also runs applications (no `CriticalAddonsOnly` taint, as the customer
requires), Spot burst pool, Standard Load Balancer egress (NAT Gateway or UDR is preferred for
production), legacy `omsagent` Container Insights, no resource locks or VNet flow logs,
a 10 GB/day Log Analytics cap (data above it is dropped), 4 storage private endpoints, and
zones 2 and 3 only (zone 1 is restricted for the subscription).

All minimal stages use `swedencentral`, including the regional AKS DNS zone
`privatelink.swedencentral.azmk8s.io`. Hub, spoke and cluster resource names use
the new region suffix consistently. The runbook selects Sweden Central for
`minimal`; `dev` and `standalone` retain UK South.

Keep legacy module resource-name parameters nonempty and distinct even when
their deployment flags are disabled. Empty names can produce colliding nested
deployment names during ARM validation; specifying names does not enable resources.

| Pool | Mode | Nodes | VM size | vCPUs / RAM per node | Priority |
| --- | --- | --- | --- | --- | --- |
| `base` | System + applications | 3 (fixed) | `Standard_D16ads_v6` | 16 / 64 GB | Regular |
| `burst` | User (jobs) | 0-1 | `Standard_D32ads_v6` | 32 / 128 GB | Spot |
| `burstmemory` | User (jobs, temporary) | 0-1 | `Standard_E32ads_v6` | 32 / 256 GB | Regular |

## Node pools and ephemeral OS disks

The minimal profile selects AMD v6 sizes with local NVMe storage and explicitly
sets `osDiskType = 'Ephemeral'` on all three pools. Ephemeral OS disks provide
lower local read/write latency and faster node provisioning, reimaging and
upgrade replacement, without a separate managed OS disk charge. This suits
replaceable AKS nodes and the scale-to-zero burst pools. The previous Dsv6/Esv6
sizes have no local storage and cannot use ephemeral OS disks.

The selected [Dadsv6](https://learn.microsoft.com/azure/virtual-machines/sizes/general-purpose/dadsv6-series)
and [Eadsv6](https://learn.microsoft.com/azure/virtual-machines/sizes/memory-optimized/eadsv6-series)
sizes retain the existing CPU/RAM tiers. Each has 440 GiB per local NVMe disk:
two disks on `base`, four on each burst size. The configured OS disk sizes remain
128 GiB (`base`), 60 GiB (`burst`) and 128 GiB (`burstmemory`), fitting within one
local disk. NVMe ephemeral OS placement consumes whole local disks; unused
capacity on the disk used for the OS is not returned as separate temporary storage.

AMD v6 was chosen over equivalent Intel local-storage v6 sizes for its lower
Sweden Central Linux retail compute prices in the 11 November 2026 comparison.
If AMD capacity is unavailable, the following Intel v6 alternatives preserve
CPU/RAM and support ephemeral OS disks, but have different pricing and I/O limits:

| Pool | Selected AMD v6 | Intel v6 alternative |
| --- | --- | --- |
| `base` | `Standard_D16ads_v6` | `Standard_D16ds_v6` |
| `burst` (Spot) | `Standard_D32ads_v6` | `Standard_D32ds_v6` |
| `burstmemory` | `Standard_E32ads_v6` | `Standard_E32ds_v6` |

Ephemeral OS data can be lost when nodes are replaced, reimaged or moved to
another host. Keep durable application data on persistent volumes or external
services, not the node OS disk. For an existing managed-OS-disk cluster, create
replacement pools, migrate workloads with appropriate disruption safeguards,
and retire old pools explicitly; this is not an in-place OS disk conversion.
See [AKS ephemeral OS disks](https://learn.microsoft.com/azure/aks/concepts-storage#ephemeral-os-disks-in-aks).

`burstmemory` is needed for three months only (tagged `expiresOn: 2027-02-11`).
To retire it, remove its entry from `additionalNodePools` and run
`az aks nodepool delete --cluster-name <cluster> --resource-group <rg> --name burstmemory`.
Raise `maxCount` on the burst pools when jobs need more parallelism and quota allows.
Workloads must tolerate the pool taints (`kubernetes.azure.com/scalesetpriority=spot` or
`workload=burst-memory`) and can select pools with the `workload` node label.

Additional pools are defined in `additionalNodePools` in each environment's
[AKS parameter file](../environments/minimal/05-AKS/main.bicepparam), using the
typed AVM agent pool schema. Add or remove entries to configure any number of
additional pools, or set `additionalNodePools = []` for only the system pool on
a new cluster. Removing an entry does not delete an existing pool during an
incremental deployment.
Each entry controls its name, VM size, count, autoscaling bounds, OS disk type and size,
priority, labels and taints. Omitted `availabilityZones` and
`vnetSubnetResourceId` inherit the cluster's zones and AKS subnet; either can be
overridden per pool. The system pool retains its `aksSystemPool*` parameters,
including optional `aksSystemPoolOSDiskType` (`Managed` or `Ephemeral`); omitting
it preserves AKS automatic disk-type selection for other profiles.
`enableAutoScaling` controls that pool and the cluster autoscaler profile,
while each additional pool specifies its own `enableAutoScaling`.
The former `aksUserPool*` and `aksThirdPool*` parameters have been replaced by
these entries without changing the existing profiles' pool settings.

The profile retains zones `2` and `3`, avoiding the previously observed zone `1`
restrictions. On 11 November 2026, the subscription's Azure Compute SKU listing
reported all three selected AMD v6 sizes in Sweden Central with ephemeral OS
disk and encryption-at-host support, all three zones and no SKU restrictions.
The Intel alternatives have not been checked in the subscription. Before
deployment, recheck AKS SKU support, zone restrictions, family and regional vCPU
quota and Spot capacity. Neither a SKU listing nor a retail price entry guarantees
allocatable capacity. The subscription what-if completed but marked the AKS
cluster as `Ignore`, so it did not validate the node-pool changes or migration.

The `base` pool is fixed at 3 nodes (48 regular vCPUs); the burst pools scale from 0 to 1
node each. At peak this is five nodes: 80 regular vCPUs and 32 Spot vCPUs. Allow
additional quota for upgrade surge; for example, one extra D16ads v6 node requires 96
regular vCPUs at peak.

The Spot pool uses `Delete` eviction and `spotMaxPrice = -1` (no price-based
eviction up to the regular VM price). Azure can still reclaim it, and allocation
is not guaranteed even when quota is available. Workloads must tolerate
`kubernetes.azure.com/scalesetpriority=spot:NoSchedule` and use the Spot label
to target this pool. A single Spot node or a single burstmemory node is not
highly available. Spot priority is immutable on an existing pool; do not treat
this configuration as an in-place conversion of a regular pool.

## Identity, versions and access

The runbook uses the active Azure CLI subscription for all stages, without storing
its ID in source; the hub uses `AKS_HUB_SUBSCRIPTION_ID` when set. It sets `HUB_SUBSCRIPTION_ID` and `DNS_SUBSCRIPTION_ID` for the
parameter files. Set your Entra groups' object IDs before validation or deployment:

```powershell
$env:AKS_ADMIN_GROUP_ID = '<admin-group-object-id>'
$env:AKS_USERS_GROUP_ID = '<users-group-object-id>'
```

The admin group receives AKS Entra administrator and cluster-admin access; the
users group receives cluster-user access. No tenant-specific group IDs are stored
in the profile, and compilation fails if either variable is missing.

The profile pins Kubernetes `1.36.5`: the latest advertised patch of Sweden
Central's default stable minor (`1.36`), which advertises `AKSLongTermSupport`
support, verified on 2026-11-11. LTS is explicitly enabled with
`aksSupportPlan = 'AKSLongTermSupport'` and `skuTier = 'Premium'`. Premium tier
has additional charges. Kubernetes version upgrades are manual in minimal
(`aksUpgradeChannel = 'none'`), so the customer decides when to move versions, for example
with `az aks upgrade`; node OS images stay managed through the `NodeImage` channel and
are applied inside the weekly maintenance window. Other profiles keep the default channel
(`patch` with LTS, otherwise `stable`); set `aksUpgradeChannel` to override it. The cluster
auto-upgrade maintenance window is only created when a channel other than `none` is used.
Plan manual upgrades before the Kubernetes minor leaves support (or LTS ends).
Recheck regional versions with `az aks get-versions --location swedencentral`
before deployment.

## Deployment and migration cautions

Choose globally unique storage account names before deployment.
An image registry is still needed for workload
images, but it does not have to be an ACR created by this repository.
Private cluster administration requires an existing VPN, private-connected
agent or other reachable management host; this profile provides no Bastion.

The profile uses separate storage account names but still shares the DNS resource
group with other profiles. Recheck global account-name availability and review
the shared DNS scope before deploying profiles simultaneously.
Changing region creates a new hub/spoke/cluster, not a relocation of existing
resources. Incremental deployments do not delete previously deployed
firewalls, gateways, ACRs, vaults, accounts or DNS zones. VNet subnet arrays are
authoritative: removing an existing subnet can delete it or fail if it is in use.
Do not apply this topology to an existing deployment without a subnet migration
review, or treat these flags as automated shared-resource cleanup.

The new optional flags default to the previous behavior. Supporting services
fall back to `storageAccountName` when `storageAccountNames` is omitted, with a
Files-only endpoint by default. Omitting `storagePublicNetworkAccess` retains
the AVM default. Keep supporting `deployACR`/`deployKeyVault` aligned with AKS
`enableACRIntegration`/`enableKeyVaultIntegration`; no registry/vault is required
when both corresponding flags are false.

Follow the [deployment and validation steps](./deployment.md) in stage order.
For firewall variants, DNS links and shared DNS migrations, see
[networking and private DNS](./networking.md).
