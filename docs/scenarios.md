# Deployment scenarios

[Overview](../README.md) | [Deployment guide](./deployment.md) | [Networking and private DNS](./networking.md)

## Choose a scenario

| Scenario | Network settings | AKS outbound | Deployment order |
| --- | --- | --- | --- |
| [New hub](#new-hub) | `connectToHub = true`; new hub identifiers; optional firewall IP | `userDefinedRouting` with firewall; otherwise `loadBalancer` | Hub, DNS creation, network, DNS links, supporting, AKS |
| [Existing hub](#existing-hub) | `connectToHub = true`; existing hub identifiers; optional firewall IP | `userDefinedRouting` with firewall; otherwise `loadBalancer` | Optional DNS creation, network, DNS links, supporting, AKS |
| [Standalone](#standalone) | `connectToHub = false`; omit hub/firewall inputs | `loadBalancer` | Optional DNS creation, network, DNS links, supporting, AKS |
| [Minimal hub](./minimal.md) | `environments\minimal`; hub peering, no firewall or ingress | `loadBalancer` | Hub, DNS creation, network, DNS links, supporting, AKS |

Optional shared monitoring runs before these stages. AKS's API stays private in
every scenario. When deployed, Application Gateway remains public; its AKS
ingress add-on retains the setting in your selected AKS parameter file.

Profiles reuse dev resource names: they are alternatives, not isolated
environments to deploy together. Review an existing deployment's routing before
switching scenarios.

## New hub

Use the [dev profile](../environments/dev/) for a hub-connected deployment with
firewall configuration.

1. Set `$environment = 'dev'` and `$deployHub = $true` in
   [deployment.azcli](../deployment.azcli).
2. Customize the [hub parameters](../environments/dev/02-Network-Hub/main.bicepparam)
   and [spoke parameters](../environments/dev/03-Network-LZ/main.bicepparam).
   Keep `connectToHub = true` and match the hub identifiers.
3. Deploy the hub before the spoke. Copy the actual hub `firewallPrivateIp`
   output into the spoke's `firewallIP`; do not assume a fixed address.
4. With a firewall, use `aksOutboundType = 'userDefinedRouting'` in the
   [AKS parameters](../environments/dev/05-AKS/main.bicepparam). Without a firewall,
   leave `firewallIP` empty and use `loadBalancer`; see
   [optional firewall](./networking.md#optional-firewall).
5. Follow the [deployment guide](./deployment.md) for DNS, supporting services,
   AKS and verification.

The runbook uses UK South for `dev`. Resource names in the profile are
environment-specific; replace them before deployment. Supply your Entra group
object IDs through `AKS_ADMIN_GROUP_ID` and `AKS_USERS_GROUP_ID`.

## Existing hub

Use the [dev profile](../environments/dev/), but skip hub creation. For a guided,
step-by-step run, see the [existing hub walkthrough](./existing-hub-walkthrough.md).

1. Set `$environment = 'dev'` and `$deployHub = $false` in
   [deployment.azcli](../deployment.azcli).
2. Set `hubResourceGroupName` and `hubVnetName` in the
   [spoke parameters](../environments/dev/03-Network-LZ/main.bicepparam) to the
   existing hub and keep `connectToHub = true`.
3. For a hub in another subscription of the same tenant, set
   `$env:AKS_HUB_SUBSCRIPTION_ID` before running the runbook. The runbook checks
   that the named hub VNet exists and registers the required hub providers.
4. If using the existing firewall, set `firewallIP` to its reachable private IP
   and AKS `aksOutboundType = 'userDefinedRouting'`. The hub owner must approve/add
   firewall rules and IP-group CIDRs for the new AKS subnets. This code does not
   change an existing shared firewall.
5. Without a firewall, leave `firewallIP` empty and use `loadBalancer`.
6. Create missing private DNS zones or reuse existing ones, then deploy the
   spoke, DNS links, supporting services and AKS. Follow the
   [DNS linking guidance](./networking.md#private-dns-is-independent) to avoid
   duplicate links. The runbook includes a DNS creation command; when reusing
   zones, review or skip that command explicitly.

The deployment identity needs permissions on both VNets for reciprocal peerings,
as well as the DNS and AKS role-assignment permissions in the
[deployment guide](./deployment.md#permissions-and-provider-registration).

## Standalone

Use the [standalone profile](../environments/standalone/).

1. Set `$environment = 'standalone'` in [deployment.azcli](../deployment.azcli).
   This profile has no hub stage.
2. Keep `connectToHub = false` and omit hub/firewall inputs in the
   [network parameters](../environments/standalone/03-Network-LZ/main.bicepparam).
3. Keep `aksOutboundType = 'loadBalancer'` in the
   [AKS parameters](../environments/standalone/05-AKS/main.bicepparam).
4. Set `AKS_ADMIN_GROUP_ID`, `AKS_USERS_GROUP_ID` and `AKS_KUBERNETES_VERSION`
   in the PowerShell environment before validation or deployment.
5. Follow the [deployment guide](./deployment.md), starting with optional
   monitoring and DNS creation, then network, DNS links, supporting services
   and AKS. Review or skip DNS creation when reusing existing zones.

Standalone uses an explicit Standard Load Balancer outbound path with a public
egress IP, not a firewall or implicit VM internet access. It retains the AKS
route table without firewall routes. The network stage attaches AKS/Application
Gateway NSGs and route tables when creating subnets; no separate subnet-update
deployment is needed.

The runbook uses UK South for `standalone`. No hub peering does not mean public
AKS management: arrange a private management path to the cluster.

## Parameter file layout

Templates remain in the numbered root folders. All `.bicepparam` files live in
[environments](../environments/), grouped by deployment profile and then stage:

```text
environments\
  baseline\
  dev\
  standalone\
  minimal\
    02-0-Monitoring\main.bicepparam
    02-Network-Hub\main.bicepparam
    03-0-DNSZones\main.bicepparam
    03-0-DNSZones\links.bicepparam
    03-Network-LZ\main.bicepparam
    04-AKS-Supporting\main.bicepparam
    05-AKS\main.bicepparam
```

| Profile | Contents |
| --- | --- |
| [baseline](../environments/baseline/) | Original baseline/example values, including optional hub VM and route-association parameters. Not an additional tested deployment scenario or a runbook environment selection. |
| [dev](../environments/dev/) | Hub-connected dev deployment, with firewall configuration. |
| [standalone](../environments/standalone/) | Standalone deployment without a hub stage. |
| [minimal](../environments/minimal/) | Sweden Central: one-subnet hub, no ingress/firewall, two storage accounts and private AKS. |

Stage parameter files are named `main.bicepparam`; the profile folder replaces
the old `-dev`, `-standalone` and `-minimal` suffixes. Each file's `using` points
back to its root-stage template. DNS creation/linking and supporting-service
parameters are included in each applicable profile so profiles can be edited
independently. Run commands from the repository root.
