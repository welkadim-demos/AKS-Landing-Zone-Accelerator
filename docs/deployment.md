# Deployment and validation

[Overview](../README.md) | [Scenarios](./scenarios.md) | [Minimal hub](./minimal.md) | [Networking and private DNS](./networking.md)

## Prerequisites

Use Azure CLI, PowerShell 7.3+ and current Bicep (validated with 0.49.2).
Sign in with `az login` and select the workload subscription with `az account set`.
Run all commands from the repository root.

Choose a [scenario and parameter profile](./scenarios.md) before deploying.
In [deployment.azcli](../deployment.azcli), set `$environment` to `minimal`
(the default), `dev` or `standalone`, then run the commands in order in PowerShell.
Each deployment uses `--confirm-with-what-if` to show changes and request approval.
Set `$deployHub = $false` when reusing an existing hub.

## Deployment order

| Stage | Purpose |
| --- | --- |
| [01-EID](../01-EID/) | Prepare Entra groups for AKS administrators and users. |
| [02-0-Monitoring](../02-0-Monitoring/) | Optional shared Log Analytics workspace and subscription Activity Log diagnostics. |
| [02-Network-Hub](../02-Network-Hub/) | Create the hub, unless using an existing hub or standalone. |
| [03-0-DNSZones](../03-0-DNSZones/main.bicep) | Create private DNS zones, unless reusing existing ones. |
| [03-Network-LZ](../03-Network-LZ/) | Create the workload VNet, subnet associations and optional Application Gateway. |
| [DNS links](../03-0-DNSZones/links.bicep) | Link existing zones after the selected VNets exist. |
| [04-AKS-Supporting](../04-AKS-Supporting/) | Deploy supporting services, identity and private endpoints. |
| [05-AKS](../05-AKS/) | Deploy private AKS and related role assignments. |
| [06-Databases](../06-Databases/) | Optional later database deployment; resource-group scoped, with no parameter file or runbook step. |

## Configure and validate

1. Prepare Entra groups using [01-EID](../01-EID/). Choose an available Kubernetes
   version with `az aks get-versions` in the workload subscription and region.
2. Edit the selected parameter files. Match network names/subnets across network,
   supporting and AKS stages; match the DNS subscription/RG/zone names across
   creation, linking, private endpoints, and AKS. For spoke-local DNS, set the DNS
   RG to the spoke RG in all those files.
3. Hub and DNS subscriptions may differ from the workload subscription. The
   runbook defaults both to the active subscription. To put the hub in another
   subscription of the same tenant, set `$env:AKS_HUB_SUBSCRIPTION_ID` before running
   it (no ID is stored in source); with `$deployHub = $true` the hub stage deploys there,
   and with `$deployHub = $false` an existing hub is used instead, after the runbook
   checks that the hub VNet named in the spoke parameters
   (`hubResourceGroupName`, `hubVnetName`) exists. The runbook also registers
   `Microsoft.Network` and `Microsoft.Insights` in the hub subscription. Edit
   `$dnsSubscriptionId` for a separate DNS subscription. It exports
   `HUB_SUBSCRIPTION_ID` and `DNS_SUBSCRIPTION_ID` for the parameter files.
   When running Bicep directly, set these environment variables yourself.
   Resource names in the [dev files](../environments/dev/) remain
   environment-specific; update them for your environment.
4. All AKS profiles read `AKS_ADMIN_GROUP_ID` and `AKS_USERS_GROUP_ID` from the
   environment. Set them to your Entra groups' object IDs before validation:

   ```powershell
   $env:AKS_ADMIN_GROUP_ID = '<admin-group-object-id>'
   $env:AKS_USERS_GROUP_ID = '<users-group-object-id>'
   ```

   Standalone also reads `AKS_KUBERNETES_VERSION` from the environment; the other
   profiles pin their Kubernetes version directly. The DNS-link example reads
   `SPOKE_VNET_RESOURCE_ID` (the runbook obtains it from the network output).
   These examples intentionally fail compilation when required inputs are absent.
5. Run the preflight before deployment:

   ```powershell
   .\Test-DeploymentConfiguration.ps1 `
     -NetworkParametersFile .\environments\minimal\03-Network-LZ\main.bicepparam `
     -AKSParametersFile .\environments\minimal\05-AKS\main.bicepparam
   ```

   Replace `minimal` with your selected profile. The
   [preflight](../Test-DeploymentConfiguration.ps1) compiles both files and rejects
   missing hub inputs, invalid firewall IPs, incompatible egress, missing required
   subnets, mismatched network/AKS names, an AKS Application Gateway add-on without
   a deployed gateway, or LTS without Premium tier. Gateway subnet/name checks are
   conditional on gateway deployment/integration. It is local validation, not an
   Azure permission, quota, DNS reachability or firewall check. The Bicep templates
   are also directly usable; run this preflight yourself if bypassing the runbook.
6. Run `bicep lint`, `bicep build`, and `bicep build-params` for your selected files.
   The runbook's `az deployment sub create --confirm-with-what-if` previews each
   stage and asks for approval before creating resources. When deploying directly,
   run `az deployment sub what-if` first. Later-stage previews require earlier
   resources to exist.

## Permissions and provider registration

- The deployment identity needs rights to create reciprocal peerings on both
  VNets (or, with `createHubPeering = false`, only on the spoke VNet), create links and private-endpoint DNS groups in the DNS scope, and assign
  roles for AKS. AKS receives DNS and network roles before cluster creation.
- Register `Microsoft.ContainerService` in both the workload and DNS subscriptions
  when the custom AKS zone is cross-subscription. Register the other relevant
  providers and wait for `EncryptionAtHost` feature registration before deployment.
  The runbook waits for provider registration and stops if `EncryptionAtHost` is
  not registered. If needed, perform this one-time setup in the workload subscription,
  wait until the second command reports `Registered`, then run the runbook again:

  ```powershell
  az feature register --namespace Microsoft.Compute --name EncryptionAtHost
  az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state --output tsv
  ```

- When using a firewall, the existing-hub owner must approve/add firewall rules
  and IP-group CIDRs for the new AKS subnets. This code does not change an existing
  shared firewall.
- Hub creation exposes `vnetResourceId` and `firewallPrivateIp`; copy the actual
  values into network inputs instead of assuming the firewall receives a fixed IP.
  If no firewall is deployed or used, leave the spoke `firewallIP` empty instead.
- Do not commit subscription IDs, passwords or secrets. Pass the database
  `pgAdministratorLoginPassword` parameter securely at deployment time.

## Security and operations

Shared template capabilities (minimal sets the corresponding parameters):

- **Tags**: every stage accepts `tags`; minimal sets `environment` and `workload`.
- **Network**: NSG on every non-reserved subnet; the private-endpoint subnet allows
  TCP 443/445 only from `privateEndpointAllowedSourcePrefixes` (the AKS subnet) and
  enforces NSGs on private endpoints; peering forwards traffic only when a firewall is used.
- **Storage**: Microsoft Entra authentication by default (`storageAllowSharedKeyAccess = false`;
  set `true` only for Azure Files SMB mounts that need account keys), deny-by-default
  network ACLs, file share soft delete. The ACR admin user is disabled.
- **AKS**: minimal uses manual Kubernetes upgrades (`aksUpgradeChannel = 'none'`)
  with managed node image updates in a weekly Sunday 02:00 UTC maintenance window.
  Other profiles keep the default upgrade channel (`patch` with LTS, otherwise
  `stable`); set `aksUpgradeChannel` to override it.
  Shared settings include a read-only node resource group, Image Cleaner, Azure
  network policy and dataplane (Cilium is available through
  `aksNetworkDataplane`/`aksNetworkPolicy`), and cluster-scoped Entra roles: both
  groups get Cluster User; admins also get RBAC Cluster Admin and users get RBAC
  Reader. The Cluster Admin credential role was removed because local accounts
  are disabled. The control-plane identity has Network Contributor on the AKS
  subnet only; the unnecessary Managed Identity Operator and VM Contributor
  assignments were removed.
- **Policy**: no Azure Policy assignments are deployed. AKS uses only the Azure Policy
  add-on (`enableAzurePolicy = true`); assign policies or initiatives to the cluster
  outside this repository (for example through your governance team).

### Optional monitoring and diagnostics

Stage [02-0-Monitoring](../02-0-Monitoring/) creates one shared Log Analytics
workspace and sends the subscription Activity Log to it. The runbook then exports
`LOG_ANALYTICS_WORKSPACE_ID`, which every stage's parameter file reads. When it is set,
the hub, spoke, supporting, database and AKS stages add diagnostic settings to VNets,
NSGs, public IPs, Firewall, Bastion, Application Gateway, storage accounts (account,
blob, file, queue and table), ACR, Key Vault, PostgreSQL, Redis and the AKS control
plane (`kube-audit-admin`, not the high-volume `kube-audit`).

To skip it, set `$deployMonitoring = $false`; to reuse an existing workspace, also
set `$env:LOG_ANALYTICS_WORKSPACE_ID` to its resource ID. Without a workspace, no
diagnostic settings are created and AKS keeps creating its own workspace for
Container Insights.

## Verify the deployment

After deployment, check peering state, subnet associations, AKS provisioning and
outbound connectivity. Test ACR, Key Vault, file-storage and AKS private-name
resolution from inside the VNet for the services you enabled. Private AKS management
needs an accessible in-VNet host, VPN, or another private management path; outbound
internet access alone does not make `kubectl` reachable.

Run the local [scenario regression checks](../tests/Test-DeploymentScenarios.ps1)
(they compile every environment parameter file, inject temporary test inputs and
restore the caller's environment):

```powershell
.\tests\Test-DeploymentScenarios.ps1 -BicepPath '<path-to-bicep.exe>'
```

## Scope and migrations

Databases remain an optional later deployment. The repository does not add NAT
Gateway, DNS Private Resolver, firewall DNS proxy, a root orchestrator, or an
isolated/no-egress cluster mode. No shared-resource cleanup is included.

Incremental deployments do not delete resources simply because deployment flags
are disabled. VNet subnet arrays are authoritative: removing a subnet can delete
it or fail if it is in use. Review subnet, routing and DNS migrations before
changing a live environment; see [networking](./networking.md) and the
[minimal profile cautions](./minimal.md#deployment-and-migration-cautions).
