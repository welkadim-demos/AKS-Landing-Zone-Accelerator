# Copilot instructions — AKS Landing Zone Accelerator

Bicep infrastructure-as-code that deploys a private AKS landing zone on Azure (hub-and-spoke network, supporting services, AKS cluster, optional databases). Everything is deployed with Azure CLI (`az deployment sub create`) and `.bicepparam` files. There is no application code.

## Current goal

Modernise the templates to the **latest Azure Verified Modules (AVM)** from the public Bicep registry (`br/public:avm/...`), replace the remaining hand-written modules in `modules/` with AVM equivalents where one exists, and validate by deploying the `dev` environment.

## Repository layout and deployment order

Folders are numbered; deploy them in this order. Each has a `main.bicep` (`targetScope = 'subscription'` unless noted). Parameter files live under `environments/<profile>/<stage>/`, not beside templates.

| Folder | Purpose | Param files |
|---|---|---|
| `01-EID/` | Entra ID groups for AKS admins/devs (`ad-groups.azcli`, `ad-groups.ps1`) | n/a |
| `02-0-Monitoring/` | Optional shared Log Analytics workspace and subscription Activity Log diagnostics. Its resource ID is exported as `LOG_ANALYTICS_WORKSPACE_ID`; every stage adds diagnostic settings only when it is set | `main.bicepparam` in each profile |
| `02-Network-Hub/` | Hub RG, VNet, optional Azure Firewall + policy, Bastion, IP group, route table. Extras: `updateUDR.bicep` (route table association), `deploy-vm.bicep` (jump box) | `main.bicepparam` in baseline/dev/minimal; auxiliary files in baseline |
| `03-0-DNSZones/` | Independent zone creation; `links.bicep` links existing zones to selected VNets after network deployment | `main.bicepparam`, `links.bicepparam` in each profile |
| `03-Network-LZ/` | Hub-connected or standalone VNet, NSGs, route tables, optional Application Gateway + public IP. NSG/UDR associations are configured in the initial subnet deployment | `main.bicepparam` in each profile |
| `04-AKS-Supporting/` | Optional ACR/Key Vault, storage accounts, user-assigned identity, private endpoints | `main.bicepparam` in each profile |
| `05-AKS/` | AKS managed cluster (uses the shared workspace or creates its own), role assignments, optional Key Vault access policy | `main.bicepparam` in each profile |
| `06-Databases/` | PostgreSQL Flexible Server + Azure Managed Redis. **`targetScope = 'resourceGroup'`**, no param file yet | none |
| `modules/` | Local, hand-written Bicep modules (legacy; see below) | n/a |
| `environments/` | Deployment profiles: baseline, dev, standalone and minimal, each with numbered stage subfolders | All `.bicepparam` files |

`deployment.azcli` is a simple PowerShell runbook selected by `$environment` (minimal by default, dev or standalone). It uses the active subscription, supports separate hub/DNS subscriptions, and previews each stage with `--confirm-with-what-if`. Set `$deployHub = $false` for an existing hub. DNS creation/linking are independent; links run after VNets exist. No cleanup commands are included. `Test-DeploymentConfiguration.ps1` checks matching network/AKS inputs and egress before deployment. See `README.md`.

## Conventions

- **Parameter files**: `environments/baseline/<stage>/main.bicepparam` holds baseline/example values; `environments/dev/<stage>/main.bicepparam` holds dev values. Standalone and minimal profiles have their own stage files. Each starts with `using '../../../<stage>/main.bicep'`. Update directly affected profiles when adding or renaming template parameters. DNS-link and auxiliary files use the corresponding root template.
- **Deployment names** follow `dev-<nn>-<stage>` (for example `dev-aks-04-aks-supporting`); resource groups follow `rg-<workload>-dev-uksouth-<nn>`.
- Default location is `uksouth`; the minimal profile uses `swedencentral` for every stage and regional resource name. Templates use `location string = deployment().location`.
- All AKS profiles read Entra group object IDs from `AKS_ADMIN_GROUP_ID` and `AKS_USERS_GROUP_ID`; do not store tenant-specific IDs in parameter files.
- Minimal uses v6 node pools in zones 2/3 and pins its regional default LTS-capable Kubernetes patch. LTS requires `skuTier = 'Premium'`, `aksSupportPlan = 'AKSLongTermSupport'` and patch-only upgrades; other profiles retain official support and stable upgrades.
- Additional AKS pools are configured through the typed `additionalNodePools` array in each environment's AKS parameter file. Omitted zones/subnet inherit the cluster settings; pool-level overrides are supported. The system pool retains its `aksSystemPool*` parameters.
- Later stages find earlier resources by **name** (`existing` resources and params such as `rgSpokevnetName`, `vnetSpokeName`, `privateDNSZoneAKSName`), so renaming a resource in one folder requires matching changes in the later folders' param files.
- Hub, workload and DNS may live in different subscriptions (`hubSubscriptionId`, `privatednszonesSubscriptionId`, `privateDNSZoneAKSNameSubscriptionId`). Deploy DNS creation/linking in the selected DNS subscription.
- Each `main.bicep` creates its own resource group through the AVM `resource-group` module.
- Do not commit subscription IDs, passwords or secrets. `06-Databases` takes `pgAdministratorLoginPassword` as a parameter, so pass it securely at deploy time rather than writing it into a param file. `Samples/` is git-ignored.

## AVM status

Already on AVM (pin exact versions, as in the existing `br/public:avm/res/<provider>/<resource>:<version>` references): resource-group, virtual-network, ip-group, firewall-policy, azure-firewall, bastion-host, route-table, network-security-group, private-dns-zone, public-ip-address, application-gateway, container-registry/registry, key-vault/vault, storage/storage-account, managed-identity/user-assigned-identity, operational-insights/workspace, container-service/managed-cluster, db-for-postgre-sql/flexible-server, cache/redis-enterprise, compute/virtual-machine.

Still local modules from `modules/` (candidates to replace with AVM or AVM role-assignment/lock/diagnostic parameters):

- `modules/vnet/privatednslink.bicep` (used by `03-0-DNSZones/links.bicep`; intentionally link-only so existing parent zones are not redeployed)
- `modules/identity/*` (role assignments in `05-AKS`)
- `modules/keyvault/keyvaultaccesspolicy.bicep`

Other files under `modules/` (`acr`, `aks`, `vm`, `storage`, `laworkspace`, most of `vnet/`) are not referenced by any `main.bicep`; confirm with a search before deleting them.

## Working rules for AVM upgrades

1. Look up the latest published version and the module's parameter/output schema (the `azure_get_azure_verified_module` tool, the Bicep registry, or <https://azure.github.io/Azure-Verified-Modules/>) before editing. Never guess parameters.
2. Upgrade one folder at a time, in deployment order, and keep parameter names stable where possible so `.bicepparam` files keep working.
3. Validate each change: `bicep build <folder>/main.bicep`, `bicep build-params environments/<profile>/<folder>/main.bicepparam`, then `az deployment sub what-if` (same arguments as the `az deployment sub create` command in `deployment.azcli`) before a real deployment.
4. Deploy and verify `dev` end to end in order 02 → 03-0 → 03 → 04 → 05 before treating the upgrade as done. Breaking AVM changes (renamed params, RBAC/role-assignment shape, subnet or NSG handling in `virtual-network`) are most likely in 03 and 05.
5. Keep the AKS cluster private: private API server with private DNS zone, Application Gateway ingress, workload identity, Azure Policy, Entra-integrated RBAC. Hub `deployFirewall` defaults to true; false skips firewall/policy/IP group and firewall routes. Peering (`connectToHub`) is independent: a nonempty spoke `firewallIP` requires `aksOutboundType = 'userDefinedRouting'`; an empty IP uses `loadBalancer`, with or without a hub. Standalone has no peerings/firewall routes.

## Skills

Project skills live in `.github/skills/` (downloaded from <https://github.com/microsoft/azure-skills>):

- `azure-enterprise-infra-planner` — hub-spoke, landing zone and Bicep architecture guidance
- `azure-kubernetes` — AKS cluster design, networking, security, upgrades
- `azure-validate` — pre-deployment validation, what-if, RBAC checks
- `azure-compliance` — azqr and security/best-practice audits
- `aks-troubleshooting` — read-only diagnosis of a live AKS cluster

To refresh them, re-copy the folders from the `azure-skills` and `aks-skills` plugins in that repository.
