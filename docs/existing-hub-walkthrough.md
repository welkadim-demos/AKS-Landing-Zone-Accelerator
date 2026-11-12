# Existing hub walkthrough

Step-by-step PowerShell guide for deploying the landing zone into an organisation
that already has a hub network. It uses
[environment-deployment.azcli](../environment-deployment.azcli), a guided runbook
that never deploys a hub and pauses before every stage. For the scenario design, see
[Existing hub](./scenarios.md#existing-hub).

## 1. Prerequisites

- PowerShell 7.3 or later (`pwsh`). Check with `$PSVersionTable.PSVersion`.
- Current Azure CLI and Bicep: `az --version`, then `az bicep upgrade`.
- Permissions on the workload subscription and on the hub VNet for reciprocal
  peerings, plus the DNS and role-assignment permissions in the
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

## 5. Set environment variables

Use the same PowerShell window for the deployment. Do not store these values in
parameter files.

```powershell
$env:AKS_ADMIN_GROUP_ID = "<object-id-of-aks-admins-group>"
$env:AKS_USERS_GROUP_ID = "<object-id-of-aks-users-group>"

# Only if the hub is in another subscription of the same tenant:
$env:AKS_HUB_SUBSCRIPTION_ID = "<hub-subscription-id>"
```

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

Review resource names, region, `kubernetesVersion` and VM sizes. Make sure the
sizes are available in the region and covered by quota. To use another profile,
change `$environment` at the top of the script (`minimal` or `dev`), or set
`$env:AKS_ENVIRONMENT` (and `$env:AKS_LOCATION`) to use a private copy such as
`environments\local`.

## 7. Run the script

```powershell
. .\environment-deployment.azcli
```

Dot-source the file: `pwsh -File` rejects it because it has no `.ps1` extension.
At each step press **ENTER** to run, **S** to skip or **Q** to quit. Every
deployment then shows a What-If; review it and answer `y` to deploy.

| Step | Action |
| --- | --- |
| 0 | Pre-checks: login, variables, hub VNet, feature registration. Cannot be skipped. |
| 1 | Register resource providers. |
| 2 | Shared Log Analytics workspace. |
| 3 | Private DNS zones. Skip when reusing existing zones. |
| 4 | Spoke network, peered with the existing hub. |
| 5 | Link DNS zones to the spoke VNet. |
| 6 | Storage, managed identity and private endpoints. |
| 7 | Private AKS cluster (roughly 10-20 minutes). |

## 8. Verify

```powershell
az aks list --output table
az network vnet peering list --resource-group <spoke-rg> --vnet-name <spoke-vnet> --output table
```

Peering state should be `Connected`. The API server is private: run
`az aks get-credentials` and `kubectl` from a machine that can reach the spoke or
hub network (jump box, Bastion or VPN).

## Troubleshooting

- **Rerun:** deployments are incremental. Rerun and skip completed steps; step 4
  outputs are read from the previous deployment.
- **Failed step:** fix the parameter file and rerun that step.
- **New window:** environment variables are lost; set them again (step 5).
- **History:** `az deployment sub list --query "[].{name:name,state:properties.provisioningState}" --output table`
