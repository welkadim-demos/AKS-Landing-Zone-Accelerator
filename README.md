# AKS landing zone

Deploy a private Azure Kubernetes Service (AKS) landing zone with Bicep Azure
Verified Modules (AVM) and Azure CLI. The templates cover networking, private DNS,
supporting services and AKS, with optional monitoring and databases.

## Choose a scenario

| Scenario | High-level design | Details |
| --- | --- | --- |
| New hub | Create a hub and peered spoke, with optional Azure Firewall egress. | [New hub guide](./docs/scenarios.md#new-hub) |
| Existing hub | Connect a new spoke to an existing hub, including cross-subscription hubs. | [Existing hub guide](./docs/scenarios.md#existing-hub) |
| Standalone | Deploy without hub peering, using Standard Load Balancer egress. | [Standalone guide](./docs/scenarios.md#standalone) |
| Minimal hub | Sweden Central hub and spoke, two storage accounts and private AKS; no firewall, ingress or databases. | [Minimal hub guide](./docs/minimal.md) |

The AKS API stays private in every scenario. Private-connected access is required
for cluster administration. When deployed, Application Gateway is public.

## Getting started

1. Install Azure CLI, PowerShell 7.3+ and current Bicep (validated with 0.49.2).
2. Choose a scenario and customize its [environment parameters](./environments/).
3. Follow the [deployment guide](./docs/deployment.md) for identity, permissions,
   validation and deployment order.
4. Select `minimal` (default), `dev` or `standalone` in
   [deployment.azcli](./deployment.azcli), then run its commands from the repository
   root in PowerShell. Each stage previews changes and requests approval.

Profiles are alternatives, not isolated environments: some resource names and DNS
scopes are shared. Review routing and migration warnings before changing an
existing deployment. No automated shared-resource cleanup is included.

## Documentation

| Guide | Contents |
| --- | --- |
| [Deployment scenarios](./docs/scenarios.md) | New hub, existing hub and standalone configuration; parameter profiles. |
| [Minimal hub](./docs/minimal.md) | Resources, node pools, ephemeral OS disks, identity, LTS and migration cautions. |
| [Deployment and validation](./docs/deployment.md) | Prerequisites, stage order, subscriptions, permissions, monitoring and verification. |
| [Networking and private DNS](./docs/networking.md) | Optional firewall, egress rules, DNS creation/linking and migration constraints. |

## Repository layout

- [Numbered stage folders](./docs/deployment.md#deployment-order) contain the Bicep
  templates, from identity preparation through optional databases.
- [environments](./environments/) contains baseline, dev, standalone and minimal
  parameter profiles.
- [modules](./modules/) contains the remaining local helper modules.
- [tests](./tests/) contains local deployment scenario regression checks.
