# Existing hub walkthrough

Step-by-step PowerShell guide for deploying the landing zone into an organisation
that already has a hub network. It uses
[environment-deployment.azcli](../environment-deployment.azcli), a list of plain
`az` commands that you paste in order; it never deploys a hub. For the scenario design, see
[Existing hub](./scenarios.md#existing-hub).

## 1. Prerequisites

- PowerShell 7.3 or later (`pwsh`). Check with `$PSVersionTable.PSVersion`.
- Current Azure CLI and Bicep: `az --version`, then `az bicep upgrade`.
- Permissions on the workload subscription. Reciprocal peering on the hub VNet is
  needed only when `createHubPeering` is `true` (the default); plus the DNS and role-assignment permissions in the
  [deployment guide](./deployment.md#permissions-and-provider-registration).
- Object IDs of the Entra groups for AKS admins and AKS users.

## 2. Open the repository

Open PowerShell 7 at the repository root (the folder containing
`environment-deployment.azcli`):

```powershell
cd C:\path\to\AKS-Landing-Zone-Accelerator-Public
```

## 3. Sign in and select the subscription

```powershell
az login
az account set --subscription "<workload-subscription-id-or-name>"
az account show --output table
```

## 4. Register EncryptionAtHost (once per subscription)

```powershell
az feature register --namespace Microsoft.Compute --name EncryptionAtHost
az feature show --namespace Microsoft.Compute --name EncryptionAtHost --query properties.state --output tsv
```

Repeat the second command until it returns `Registered` (this can take several
minutes), then run:

```powershell
az provider register --namespace Microsoft.Compute
```

## 5. Environment variables

The settings block at the top of the runbook sets these in the PowerShell window you
use for the deployment. Do not store the values in parameter files.

## 6. Enter the hub details

Edit `environments\minimal\03-Network-LZ\main.bicepparam`:

| Parameter | Value |
| --- | --- |
| `hubResourceGroupName` | Resource group of the existing hub VNet |
| `hubVnetName` | Name of the existing hub VNet |
| `firewallIP` | Private IP of the hub firewall, or `''` if there is none |
| `vnetSpokeAddressPrefixes` and subnet prefixes | Ranges that do not overlap the hub or other peered networks |

Then edit `environments\minimal\05-AKS\main.bicepparam`:

- If `firewallIP` is set, use `aksOutboundType = 'userDefinedRouting'`. The hub
  owner must add firewall rules and IP-group CIDRs for the new AKS subnets.
- If `firewallIP` is empty, keep `aksOutboundType = 'loadBalancer'`.

Nothing is deployed into the hub. To also avoid changing the hub VNet, add
`param createHubPeering = false` to the spoke parameters; the hub owner then
creates the reverse peering (see [Hub-side peering](#hub-side-peering)).

Review resource names, region, `kubernetesVersion` and VM sizes. Make sure the
sizes are available in the region and covered by quota. To use another profile,
set `$environment` in the runbook settings (`minimal`, `dev` or a private copy
such as `local`) and `$location` to its region.

## 7. Run the commands

Open [environment-deployment.azcli](../environment-deployment.azcli), replace the
placeholders in section 1, then paste each numbered block into the PowerShell 7
terminal in order (in VS Code with the Azure CLI Tools extension, run a selection
with `Ctrl+'`). Every deployment shows a What-If; review it and answer `y` to deploy.
Keep the same terminal window, because later blocks reuse its variables.

| Block | Action |
| --- | --- |
| 1-2 | Settings, sign-in and subscription. |
| 3 | Pre-checks: configuration test, feature registration, hub VNet. |
| 4 | Register resource providers. |
| 5 | Shared Log Analytics workspace. |
| 6 | Private DNS zones. Skip when reusing existing zones. |
| 7 | Spoke network, peered with the existing hub. |
| 8 | Link DNS zones to the spoke VNet. |
| 9 | Storage, managed identity and private endpoints. |
| 10 | Private AKS cluster (roughly 10-20 minutes). |
| 11 | Verify. |

## 8. Verify

```powershell
az aks list --output table
az network vnet peering list --resource-group <spoke-rg> --vnet-name <spoke-vnet> --output table
```

Peering state should be `Connected`. With `createHubPeering = false` it stays
`Initiated` until the hub owner completes the hub-side peering. The API server is private: run
`az aks get-credentials` and `kubectl` from a machine that can reach the spoke or
hub network (jump box, Bastion or VPN).

## Hub-side peering

With `createHubPeering = false`, ask the hub owner to run this once the spoke
exists. If an old, `Disconnected` peering with the same name remains, they must
delete and recreate it. Use `--allow-forwarded-traffic true` when the hub has a
firewall.

```powershell
az network vnet peering create --subscription <hub-subscription-id> --resource-group <hub-resource-group> `
  --vnet-name <hub-vnet-name> --name <hub-vnet-name>-to-<spoke-vnet-name> `
  --remote-vnet <spoke-vnet-resource-id> --allow-vnet-access true
```

## Troubleshooting

- **Rerun:** deployments are incremental. Rerun and skip completed blocks; block 7
  outputs are read from the previous deployment.
- **Failed step:** fix the parameter file and rerun that block.
- **New window:** environment variables are lost; set them again (block 1 and the sign-in in block 2).
- **History:** `az deployment sub list --query "[].{name:name,state:properties.provisioningState}" --output table`
