targetScope = 'subscription'

import { agentPoolType } from 'br/public:avm/res/container-service/managed-cluster:0.14.0'

param rgName string
param location string = deployment().location
param aksIdentityName string
param privateDNSZoneAKSName string
param privateDNSZoneAKSNameSubscriptionId string = subscription().subscriptionId
param privateDNSZoneAKSNameResourceGroup string
param akslaworkspaceName string = ''
@description('Optional. Resource ID of an existing Log Analytics workspace. When set, the workspace is not created and this one is used for AKS monitoring.')
param existingLAWorkspaceResourceId string = ''
param aksvnetName string
param vnetspokeRGName string
param akssubnetName string
param aksAppGatewayName string
param rtaksName string

param aksClusterName string
param kubernetesVersion string
@description('Optional. Name of a managed cluster SKU.')
@allowed([
  'Base'
  'Automatic'
])

param skuName string = 'Base'

@description('Optional. Tier of a managed cluster SKU.')
@allowed([
  'Free'
  'Premium'
  'Standard'
])

param skuTier string = 'Standard'
@allowed(['KubernetesOfficial', 'AKSLongTermSupport'])
param aksSupportPlan string = 'KubernetesOfficial'
param aksadminGroupaccessprincipalId string
param aksusersgroupaccessprincipalId string
param enableAzurePolicy bool = true
param enableOMSAgent bool = true
param enableIngressApplicationGateway bool = true
param availabilityZones array = []
param enableAutoScaling bool = true
param enableWorkloadIdentity bool = true
param autoScalingProfile object
@description('Azure CNI is the only supported network plugin. Kubenet is retiring in March 2028.')
@allowed([
  'azure'
])
param aksNetworkPlugin string = 'azure'
@description('Optional. Set overlay for Azure CNI Overlay; omit for VNet-routable Azure CNI.')
@allowed([
  'overlay'
])
param aksNetworkPluginMode string?
param aksPodCidr string?
param aksServiceCidr string
param aksDnsServiceIP string
param aksNetworkPolicy string = 'calico'

param aksSystemPoolVMSize string = 'Standard_D4d_v4'
@description('Name of the system pool. It also runs application workloads unless tainted.')
@minLength(1)
@maxLength(12)
param aksSystemPoolName string = 'defaultpool'
param aksSystemPoolOSDiskSizeGB int = 30
@description('Optional. System pool OS disk type. Omit to let AKS select based on VM size and disk capacity. Ephemeral requires a compatible VM with sufficient local storage.')
@allowed(['Managed', 'Ephemeral'])
param aksSystemPoolOSDiskType string?
param aksSystemPoolNodesCount int = 3
param aksSystemPoolNodeMin int = 1
param aksSystemPoolNodeMax int =3
@description('Additional node pools using the AVM agent pool schema. Omitted availability zones and subnet default to the cluster settings. Use an empty array for a system-pool-only cluster.')
param additionalNodePools agentPoolType[] = []

@description('Optional. Tags applied to all resources.')
param tags object = {}
@description('Optional. Network dataplane. Use cilium (with aksNetworkPolicy = cilium) for Azure CNI Powered by Cilium.')
@allowed(['azure', 'cilium'])
param aksNetworkDataplane string?
@description('Optional. Node OS image upgrade channel.')
@allowed(['None', 'Unmanaged', 'NodeImage', 'SecurityPatch'])
param aksNodeOSUpgradeChannel string = 'NodeImage'
@description('Optional. Cluster auto-upgrade channel. Use none for manual Kubernetes version upgrades. Defaults to patch with long-term support, otherwise stable.')
@allowed(['none', 'patch', 'stable', 'rapid', 'node-image'])
param aksUpgradeChannel string?
@description('Maintenance windows for cluster and node OS upgrades (UTC). Upgrades only run inside these windows.')
param maintenanceConfigurations array = [
  {
    name: 'aksManagedAutoUpgradeSchedule'
    maintenanceWindow: {
      schedule: {
        weekly: {
          intervalWeeks: 1
          dayOfWeek: 'Sunday'
        }
      }
      durationHours: 4
      utcOffset: '+00:00'
      startTime: '02:00'
    }
  }
  {
    name: 'aksManagedNodeOSUpgradeSchedule'
    maintenanceWindow: {
      schedule: {
        weekly: {
          intervalWeeks: 1
          dayOfWeek: 'Sunday'
        }
      }
      durationHours: 4
      utcOffset: '+00:00'
      startTime: '02:00'
    }
  }
]
@description('Optional. Resource ID of the shared Log Analytics workspace (stage 02-0-Monitoring). When set, it is used for Container Insights and AKS diagnostic settings, and no workspace is created here.')
param logAnalyticsWorkspaceResourceId string = ''

param acrName string
param keyvaultName string
@description('Grant AcrPull on the existing registry. Disable when ACR is not deployed.')
param enableACRIntegration bool = true
@description('Enable the Key Vault CSI add-on and vault access policy.')
param enableKeyVaultIntegration bool = true

@description('Optional. Specifies outbound (egress) routing method.')
@allowed([
  'loadBalancer'
  'userDefinedRouting'
  'managedNATGateway'
  'userAssignedNATGateway'
])
param aksOutboundType string = 'loadBalancer'
param aksEnableWebRoutingAddOn bool = true
param aksWebRoutingAddOnDnsZoneResourceIds array?
param enableDnsZoneContributorRoleAssignment bool = false

var effectiveUpgradeChannel = aksUpgradeChannel ?? (aksSupportPlan == 'AKSLongTermSupport' ? 'patch' : 'stable')
var aksInfrastractureRGName = 'rg-${aksClusterName}-${toLower(location)}-aksInfra'

var privateDNSZoneAKSSuffixes = {
  AzureCloud: '.azmk8s.io'
  AzureUSGovernment: '.cx.aks.containerservice.azure.us'
  AzureChinaCloud: '.cx.prod.service.azk8s.cn'
  AzureGermanCloud: '' //TODO: what is the correct value here?
}

var aksprivateDNSZone = !empty(privateDNSZoneAKSName)? privateDNSZoneAKSName : 'privatelink.${toLower(location)}${privateDNSZoneAKSSuffixes[environment().name]}'

module rg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: rgName
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

resource aksIdentity  'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  scope: resourceGroup(rg.name)
  name: aksIdentityName
}

resource privatednsAKSZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = {
  scope: resourceGroup(privateDNSZoneAKSNameSubscriptionId, privateDNSZoneAKSNameResourceGroup)
  name: aksprivateDNSZone
}

var monitoringWorkspaceId = !empty(existingLAWorkspaceResourceId) ? existingLAWorkspaceResourceId : logAnalyticsWorkspaceResourceId
var useExistingLAWorkspace = !empty(monitoringWorkspaceId)

module akslaworkspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = if (!useExistingLAWorkspace) {
  scope: resourceGroup(rgName)
  name: 'aksworkspace'
  params: {
    name: akslaworkspaceName
    location: location
    tags: tags
    dataRetention: 30
  }
  dependsOn: [
    rg
  ]
}

resource akssubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  scope: resourceGroup(vnetspokeRGName)
  name: '${aksvnetName}/${akssubnetName}'
}

resource appGateway 'Microsoft.Network/applicationGateways@2024-05-01' existing = if (enableIngressApplicationGateway) {
  scope: resourceGroup(vnetspokeRGName)
  name: aksAppGatewayName
}

module aks 'br/public:avm/res/container-service/managed-cluster:0.14.0' = {
  scope: resourceGroup(rgName)
  name: 'aks-cluster'
  params: {
    name: aksClusterName
    location: location
    tags: tags
    kubernetesVersion: kubernetesVersion
    skuName: skuName
    skuTier: skuTier
    supportPlan: aksSupportPlan
    autoUpgradeProfile: {
      upgradeChannel: effectiveUpgradeChannel
      nodeOSUpgradeChannel: aksNodeOSUpgradeChannel
    }
    maintenanceConfigurations: filter(maintenanceConfigurations, configuration => effectiveUpgradeChannel != 'none' || configuration.name != 'aksManagedAutoUpgradeSchedule')
    managedIdentities: {
      userAssignedResourceIds: [aksIdentity.id]
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
      adminGroupObjectIDs: [aksadminGroupaccessprincipalId]
      tenantID: subscription().tenantId
    }
    disableLocalAccounts: true
    enableRBAC: true
    nodeResourceGroup: aksInfrastractureRGName
    nodeResourceGroupProfile: {
      restrictionLevel: 'ReadOnly'
    }
    apiServerAccessProfile: {
      enablePrivateCluster: true
      privateDNSZone: privatednsAKSZone.id
      enablePrivateClusterPublicFQDN: false
    }

    // Network
    networkPlugin: aksNetworkPlugin
    networkPluginMode: aksNetworkPluginMode
    networkDataplane: aksNetworkDataplane
    podCidr: aksPodCidr
    serviceCidr: aksServiceCidr
    dnsServiceIP: aksDnsServiceIP
    networkPolicy: aksNetworkPolicy
    outboundType: aksOutboundType

    // Auto-scaling
    autoScalerProfile: enableAutoScaling ? autoScalingProfile : null

    // Add-ons
    azurePolicyEnabled: enableAzurePolicy
    omsAgentEnabled: enableOMSAgent
    monitoringWorkspaceResourceId: useExistingLAWorkspace ? monitoringWorkspaceId : akslaworkspace!.outputs.resourceId
    // kube-audit is excluded in favour of kube-audit-admin to avoid high-volume read events.
    diagnosticSettings: empty(logAnalyticsWorkspaceResourceId) ? [] : [
      {
        name: 'send-to-log-analytics'
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        logAnalyticsDestinationType: 'Dedicated'
        logCategoriesAndGroups: [
          { category: 'kube-apiserver' }
          { category: 'kube-audit-admin' }
          { category: 'kube-controller-manager' }
          { category: 'kube-scheduler' }
          { category: 'cluster-autoscaler' }
          { category: 'guard' }
          { category: 'csi-azuredisk-controller' }
          { category: 'csi-azurefile-controller' }
          { category: 'csi-snapshot-controller' }
        ]
        metricCategories: [
          { category: 'AllMetrics' }
        ]
      }
    ]
    ingressApplicationGatewayEnabled: enableIngressApplicationGateway
    appGatewayResourceId: enableIngressApplicationGateway ? appGateway!.id : null
    enableKeyvaultSecretsProvider: enableKeyVaultIntegration
    enableStorageProfileDiskCSIDriver: true
    enableStorageProfileFileCSIDriver: true
    enableStorageProfileSnapshotController: true
    
    // Security
    securityProfile: {
      workloadIdentity: {
        enabled: enableWorkloadIdentity
      }
      imageCleaner: {
        enabled: true
        intervalHours: 168
      }
    }
    enableOidcIssuerProfile: enableWorkloadIdentity

    // Web routing
    webApplicationRoutingEnabled: aksEnableWebRoutingAddOn
    dnsZoneResourceId: !empty(aksWebRoutingAddOnDnsZoneResourceIds ?? []) ? aksWebRoutingAddOnDnsZoneResourceIds![0] : null
    enableDnsZoneContributorRoleAssignment: false

    // Agent pools
    primaryAgentPoolProfiles: [
      {
        name: aksSystemPoolName
        count: aksSystemPoolNodesCount
        availabilityZones: availabilityZones
        enableAutoScaling: enableAutoScaling
        minCount: enableAutoScaling ? aksSystemPoolNodeMin : null
        maxCount: enableAutoScaling ? aksSystemPoolNodeMax : null
        mode: 'System'
        osDiskSizeGB: aksSystemPoolOSDiskSizeGB
        osDiskType: aksSystemPoolOSDiskType
        vmSize: aksSystemPoolVMSize
        type: 'VirtualMachineScaleSets'
        vnetSubnetResourceId: akssubnet.id
        enableEncryptionAtHost: true

      }
    ]
    agentPools: [for pool in additionalNodePools: union({
      availabilityZones: availabilityZones
      vnetSubnetResourceId: akssubnet.id
    }, pool)]
    // Cluster-scoped data-plane access. Local accounts are disabled, so the Cluster Admin credential role is not used;
    // the admin group is also cluster-admin through aadProfile.adminGroupObjectIDs.
    roleAssignments: [
      {
        principalId: aksadminGroupaccessprincipalId
        principalType: 'Group'
        roleDefinitionIdOrName: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' //Azure Kubernetes Service Cluster User Role
      }
      {
        principalId: aksadminGroupaccessprincipalId
        principalType: 'Group'
        roleDefinitionIdOrName: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b' //Azure Kubernetes Service RBAC Cluster Admin
      }
      {
        principalId: aksusersgroupaccessprincipalId
        principalType: 'Group'
        roleDefinitionIdOrName: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' //Azure Kubernetes Service Cluster User Role
      }
      {
        principalId: aksusersgroupaccessprincipalId
        principalType: 'Group'
        roleDefinitionIdOrName: '7f6c6a51-bcf8-42ba-9220-52d62157d7db' //Azure Kubernetes Service RBAC Reader
      }
    ]
  }
  dependsOn: [
    aksIdentity
    aksRouteTableRole
    akspvtNetworkContributor
    aksPvtDNSContributor
    akssubnet
    appGateway
  ]
}


module aksRouteTableRole '../modules/Identity/rtrole.bicep' = {
  scope: resourceGroup(vnetspokeRGName)
  name: 'aksRouteTableRole'
  params: {
    principalId: aksIdentity.properties.principalId
    roleGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' //Network Contributor
    rtName: rtaksName
  }
}

// Grant AcrPull on the ACR to the AKS *kubelet* identity (the one that
// actually pulls container images), NOT the control-plane identity.
// AVM exposes the auto-created kubelet identity's object ID as an output.
module acraksaccess '../modules/Identity/acrrole.bicep' = if (enableACRIntegration) {
  scope: resourceGroup(rg.name)
  name: 'acraksaccess'
  params: {
    principalId: aks.outputs.kubeletIdentityObjectId!
    roleGuid: '7f951dda-4ed3-4680-a7ca-43fe172d538d' //AcrPull
    acrName: acrName
  }
}

module akspvtNetworkContributor '../modules/Identity/networkcontributorrole.bicep' = {
  scope: resourceGroup(vnetspokeRGName)
  name: 'akspvtNetworkContributor'
  params: {
    principalId: aksIdentity.properties.principalId
    roleGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' //Network Contributor
    vnetName: aksvnetName
    subnetName: akssubnetName
  }
}


module aksPvtDNSContributor '../modules/Identity/pvtdnscontribrole.bicep' = {
  scope: resourceGroup(privateDNSZoneAKSNameSubscriptionId, privateDNSZoneAKSNameResourceGroup)
  name: 'aksPvtDNSContributor'
  params: {
    principalId: aksIdentity.properties.principalId
    roleGuid: 'b12aa53e-6015-4669-85d0-8515ebb3ae7f' //Private DNS Zone Contributor
    pvtdnsAKSZoneName: privatednsAKSZone.name
  }
  dependsOn: [    
    privatednsAKSZone
  ]
}

module appGatewayContributorRole '../modules/Identity/role.bicep' = if (enableIngressApplicationGateway) {
  scope: resourceGroup(vnetspokeRGName)
  name: 'appGatewayContributor'
  params: {
    principalId: aks.outputs.ingressApplicationGatewayIdentityObjectId!
    roleGuid: 'b24988ac-6180-42a0-ab88-20f7382dd24c' //Application Gateway Contributor
  }
}

module appGatewayReaderRole '../modules/Identity/role.bicep' = if (enableIngressApplicationGateway) {
  scope: resourceGroup(vnetspokeRGName)
  name: 'appGatewayReader'
  params: {
    principalId: aks.outputs.ingressApplicationGatewayIdentityObjectId!
    roleGuid: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' //Reader
  }
}

module keyvaultAccessPolicy '../modules/keyvault/keyvaultaccesspolicy.bicep' = if (enableKeyVaultIntegration) {
  scope: resourceGroup(rgName)
  name: 'keyvaultAccessPolicy'
  params: {
    aksuseraccessprincipalId: aks.outputs.keyvaultIdentityObjectId!
    vaultName: keyvaultName
    keyvaultManagedIdentityObjectId: aksusersgroupaccessprincipalId
  }
}

module dnsZoneRoleAssignment '../modules/identity/webroutingdnsroleassignment.bicep' =  [for dnsZoneResourceId in (aksWebRoutingAddOnDnsZoneResourceIds ?? []): if(enableDnsZoneContributorRoleAssignment && aksEnableWebRoutingAddOn) {
  scope: resourceGroup(dnsZoneResourceId)
  name: 'dnsZoneRoleAssignment'
  params: {
    principalId: aks.outputs.webAppRoutingIdentityObjectId!
    roleGuid: 'b24988ac-6180-42a0-ab88-20f7382dd24c' //DNS Zone Contributor
    dnsZoneResourceId: dnsZoneResourceId
  }
}]
