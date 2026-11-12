# Networking and private DNS

[Overview](../README.md) | [Scenarios](./scenarios.md) | [Deployment guide](./deployment.md)

## Supported AKS networking

Only Azure CNI (`aksNetworkPlugin = 'azure'`) is supported. All supplied profiles
use Azure CNI Overlay (`aksNetworkPluginMode = 'overlay'`). VNet-routable Azure CNI
remains available by omitting the optional network plugin mode.

Kubenet is no longer offered because it retires in March 2028. The AKS template
and configuration validator reject it, and Kubenet-specific Application Gateway
pod routes have been removed. The AKS stage no longer takes `rtAppGWSubnetName`;
the network stage still manages the Application Gateway subnet route table.
This change does not migrate existing clusters or delete their routes. Plan an
explicit [migration to Azure CNI Overlay](https://learn.microsoft.com/azure/aks/update-azure-cni)
before redeploying an existing Kubenet cluster.

## Egress and subnet associations

Hub peering and egress routing are independent. A nonempty spoke `firewallIP`
requires AKS `aksOutboundType = 'userDefinedRouting'` and a reachable hub firewall.
An empty IP uses `loadBalancer`, with or without a hub.

The network stage attaches AKS/Application Gateway NSGs and route tables when
creating the subnets. No separate subnet-update deployment is needed. Standalone
retains the AKS route table without firewall routes.

## Optional firewall

The hub's `deployFirewall` defaults to `true`, preserving existing behavior.
Set it to `false` in the selected hub parameter file to skip Azure Firewall, its
public IPs, firewall policy/rule groups, and AKS IP group. Hub networking, Bastion
and the VM route table remain; the route table has no firewall default route.
Use `deployBastion = false` and `deployVMRouteTable = false` to omit those too.
Existing firewall-specific parameter values are ignored when disabled; reserved
firewall subnets may remain in the VNet without deploying a firewall.

For a hub-connected spoke without a firewall, keep `connectToHub = true`, omit
`firewallIP` (or set it to `''`), and set AKS `aksOutboundType = 'loadBalancer'`.
`deployFirewall` only controls firewall creation in the hub stage, not use of an
already-existing firewall.

With no firewall, `firewallPrivateIp` is `null`. Disabling firewall deployment in
incremental mode does **not** delete an existing firewall or policy. Review the
egress migration and any remaining routes explicitly before changing a live
environment; this code does not perform firewall cleanup.

## Private DNS is independent

- [Zone creation](../03-0-DNSZones/main.bicep) creates zones in its selected resource
  group/subscription. This may be a shared DNS RG or the spoke RG, with or without a hub.
- [Zone linking](../03-0-DNSZones/links.bicep) only deploys links to existing zones.
  Run it after the selected VNets exist; it does not recreate zones or change records.
- `virtualNetworkResourceIds` selects hub, spoke, both, resolver VNets, or `[]`.
  `privateDNSZoneNames` optionally selects existing zone names. By default, links
  cover ACR, Key Vault, the configured storage services, and the regional AKS zone.
  Database zones are not linked unless explicitly selected. When reusing older
  DNS deployments, create the additional storage zones first or provide an
  explicit list of existing zones. `deployDatabaseZones = false` skips database
  zone creation.
- Deploy the link stage in the **DNS subscription**, not necessarily the workload
  subscription. Set its `rgName` to the DNS RG and `location` to the AKS region.
  VNets can be in other subscriptions.
- With Azure-provided DNS (empty `dhcpOptions.dnsServers`), link zones to the spoke.
  Peering does not make DNS links transitive. With custom DNS, link zones to the
  resolver VNet and configure/test forwarding. A firewall IP is not a DNS server
  unless its DNS proxy and upstream resolution are configured.
- The default link name remains `<vnet-name>-link` to preserve existing hub links.
  Selected VNets must have distinct names within a zone. Remove duplicate VNet IDs
  from the input list. If a link already exists under another name (including one
  created by AKS), do not deploy a second link to that VNet: retain the existing
  link and omit that zone/VNet pair from this deployment. Run separate link
  deployments with explicit zone lists if different zones need different targets.
- AKS can create/manage a spoke link to its custom private DNS zone even when you
  select only hub/resolver links here. Do not remove AKS-required links.
- Removing a VNet from the list does not delete its existing link in incremental
  deployments. Review DNS migrations explicitly; no link deletion is automated.
