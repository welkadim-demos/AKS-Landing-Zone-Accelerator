targetScope = 'subscription'

param rgName string
param vnetHubName string
param hubVnetAddressPrefixes array
param hubSubnets array
@description('Deploy Azure Firewall, its policy and IP group. When false, no firewall default route is configured.')
param deployFirewall bool = true
@description('Deploy Azure Bastion. Requires a dedicated AzureBastionSubnet when enabled.')
param deployBastion bool = true
@description('Deploy the VM subnet route table.')
param deployVMRouteTable bool = true
// Firewall Policy parameters
param firewallPolicyName string
param threatIntelMode string
param firewallPolicyTier string
param applicationRuleCollectionGroupName string
param applicationRuleCollectionGroupPriority int
param applicationRuleCollections array
param networkRuleCollectionGroupName string
param networkRuleCollectionGroupPriority int
param networkRuleCollections array
param azfwName string
param rtVMSubnetname string
param aksIpGroupName string
param aksSubnetPrefixes array
param location string = deployment().location
param availabilityZones array
@description('Optional. Tags applied to all resources.')
param tags object = {}
@description('Optional. Resource ID of a Log Analytics workspace. When set, diagnostic settings are sent to it for every supported resource.')
param logAnalyticsWorkspaceResourceId string = ''
@description('NSG associated with hub subnets that are not reserved for Azure platform services.')
param nsgHubName string = 'nsg-${vnetHubName}'

var diagnosticSettings = empty(logAnalyticsWorkspaceResourceId) ? [] : [
  {
    name: 'send-to-log-analytics'
    workspaceResourceId: logAnalyticsWorkspaceResourceId
  }
]

var reservedSubnetNames = [
  'AzureFirewallSubnet'
  'AzureFirewallManagementSubnet'
  'AzureBastionSubnet'
  'GatewaySubnet'
  'RouteServerSubnet'
]
var configuredHubSubnets = map(hubSubnets, subnet => contains(reservedSubnetNames, subnet.name) ? subnet : union({
  networkSecurityGroupResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/networkSecurityGroups', nsgHubName)
}, subnet))

// Create a resource group
module rg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: '${rgName}-deployment'
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

module nsgHub 'br/public:avm/res/network/network-security-group:0.5.4' = {
  scope: resourceGroup(rgName)
  name: '${nsgHubName}-deployment'
  params: {
    name: nsgHubName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
  }
  dependsOn: [rg]
}

// Create a virtual network
module vnetHub 'br/public:avm/res/network/virtual-network:0.10.2' = {
  scope: resourceGroup(rgName)
  name: '${vnetHubName}-deployment'
  params: {
    name: vnetHubName
    location: location
    addressPrefixes: hubVnetAddressPrefixes
    subnets: configuredHubSubnets
    tags: tags
    diagnosticSettings: diagnosticSettings
  }
  dependsOn: [rg, nsgHub]
}

// Create IP Group for AKS subnets
module aksIpGroup 'br/public:avm/res/network/ip-group:0.4.0' = if (deployFirewall) {
  scope: resourceGroup(rgName)
  name: '${aksIpGroupName}-deployment'
  params: {
    name: aksIpGroupName
    location: location
    tags: tags
    ipAddresses: aksSubnetPrefixes
  }
  dependsOn: [rg]
}

// Pre-construct the IP Group resource ID for use in rule transformations
var aksIpGroupId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${rgName}/providers/Microsoft.Network/ipGroups/${aksIpGroupName}'

// Transform rule collections to use IP Group instead of hardcoded source addresses
var transformedAppRuleCollections = map(applicationRuleCollections, collection => {
  ruleCollectionType: collection.ruleCollectionType
  action: collection.action
  name: collection.name
  priority: collection.priority
  rules: map(collection.rules, rule => union(rule, {
    sourceAddresses: []
    sourceIpGroups: [aksIpGroupId]
  }))
})

var transformedNetRuleCollections = map(networkRuleCollections, collection => {
  ruleCollectionType: collection.ruleCollectionType
  action: collection.action
  name: collection.name
  priority: collection.priority
  rules: map(collection.rules, rule => union(rule, {
    sourceAddresses: []
    sourceIpGroups: [aksIpGroupId]
  }))
})

// Create firewall Policy with rule collection groups
module firewallPolicy 'br/public:avm/res/network/firewall-policy:0.4.0' = if (deployFirewall) {
  scope: resourceGroup(rgName)
  name: '${firewallPolicyName}-deployment'
  params: {
    name: firewallPolicyName
    location: location
    tags: tags
    tier: firewallPolicyTier
    threatIntelMode: threatIntelMode
    ruleCollectionGroups: [
      {
        name: applicationRuleCollectionGroupName
        priority: applicationRuleCollectionGroupPriority
        ruleCollections: transformedAppRuleCollections
      }
      {
        name: networkRuleCollectionGroupName
        priority: networkRuleCollectionGroupPriority
        ruleCollections: transformedNetRuleCollections
      }
    ]
  }
  dependsOn: [rg, aksIpGroup]
}

// Create Azure Firewall (auto-creates public IPs for firewall and management)
module azfirewall 'br/public:avm/res/network/azure-firewall:0.11.1' = if (deployFirewall) {
  scope: resourceGroup(rgName)
  name: '${azfwName}-deployment'
  params: {
    name: azfwName
    location: location
    tags: tags
    virtualNetworkResourceId: vnetHub.outputs.resourceId
    azureSkuTier: firewallPolicyTier
    firewallPolicyId: firewallPolicy!.outputs.resourceId
    availabilityZones: availabilityZones
    enableManagementNic: true
    publicIPAddressObject: {
      name: '${azfwName}-pip'
      diagnosticSettings: diagnosticSettings
    }
    managementIPAddressObject: {
      name: '${azfwName}-pip-management'
      diagnosticSettings: diagnosticSettings
    }
    diagnosticSettings: empty(logAnalyticsWorkspaceResourceId) ? [] : [
      {
        name: 'send-to-log-analytics'
        workspaceResourceId: logAnalyticsWorkspaceResourceId
        logAnalyticsDestinationType: 'Dedicated'
      }
    ]
  }
}

// Create Bastion Host (auto-creates its public IP)
module bastion 'br/public:avm/res/network/bastion-host:0.8.2' = if (deployBastion) {
  scope: resourceGroup(rgName)
  name: 'bastion-deployment'
  params: {
    name: 'bastion'
    location: location
    tags: tags
    virtualNetworkResourceId: vnetHub.outputs.resourceId
    publicIPAddressObject: {
      name: 'publicip-bastion'
      diagnosticSettings: diagnosticSettings
    }
    diagnosticSettings: diagnosticSettings
  }
}

// Create Route Table with routes (deployed after firewall to get its private IP)
module routetable 'br/public:avm/res/network/route-table:0.5.0' = if (deployVMRouteTable) {
  scope: resourceGroup(rgName)
  name: '${rtVMSubnetname}-deployment'
  params: {
    name: rtVMSubnetname
    location: location
    tags: tags
    routes: deployFirewall ? [
      {
        name: 'vm-to-internet-routes'
        properties: {
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: azfirewall!.outputs.privateIp
          addressPrefix: '0.0.0.0/0'
        }
      }
    ] : []
  }
}

output vnetResourceId string = vnetHub.outputs.resourceId
output firewallPrivateIp string? = deployFirewall ? azfirewall!.outputs.privateIp : null
