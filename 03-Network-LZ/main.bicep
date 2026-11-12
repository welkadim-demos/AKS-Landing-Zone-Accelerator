targetScope = 'subscription'

param rgName string
param location string = deployment().location

// VNet spoke parameters
param vnteSpokeName string
param vnetSpokeAddressPrefixes array
param vnetSpokeSubnets array
param dhcpOptions object = {}

param nsgAKSName string
param rtAKSSubnetname string
param aksSubnetName string = 'AKS'

@description('Connect to a new or existing hub. Set false for a standalone network.')
param connectToHub bool = true
@description('Optional hub firewall next-hop IP. Leave empty to use AKS loadBalancer outbound without a firewall route.')
param firewallIP string = ''
@description('Create the hub-side peering as well. Set false to leave the existing hub untouched; the hub owner must then create the reverse peering.')
param createHubPeering bool = true

@description('Optional. AKS service CIDR. When provided, a UDR with VnetLocal next hop is added so service traffic does not transit the firewall.')
param aksServiceCidr string?

@description('Optional. AKS pod CIDR. When provided, a UDR with VnetLocal next hop is added so pod-to-pod traffic does not transit the firewall.')
param aksPodCidr string?

param hubVnetName string = ''
param hubSubscriptionId string = ''
param hubResourceGroupName string = ''

@description('Deploy Application Gateway and its public IP, NSG and route table.')
param deployApplicationGateway bool = true
param appgwpipName string
param appgwsubnetName string
param appgwName string
param availabilityZones array
param appgwAutoScale object
param nsgappgwName string
param appgwroutetableName string

@description('Optional. Tags applied to all resources.')
param tags object = {}
@description('Optional. Resource ID of a Log Analytics workspace. When set, diagnostic settings are sent to it for every supported resource.')
param logAnalyticsWorkspaceResourceId string = ''

var diagnosticSettings = empty(logAnalyticsWorkspaceResourceId) ? [] : [
  {
    name: 'send-to-log-analytics'
    workspaceResourceId: logAnalyticsWorkspaceResourceId
  }
]

@description('Name of the subnet that hosts private endpoints.')
param privateEndpointSubnetName string = 'servicespe'
@description('Optional. Source address prefixes allowed to reach private endpoints (TCP 443 and 445). When set, all other inbound VNet traffic to the private endpoint subnet is denied; otherwise the subnet uses the default NSG rules.')
param privateEndpointAllowedSourcePrefixes string[] = []
param nsgPrivateEndpointName string = 'nsg-${vnteSpokeName}-pe'
@description('NSG for subnets that are not AKS, Application Gateway or private endpoint subnets.')
param nsgDefaultName string = 'nsg-${vnteSpokeName}-default'

var hubVnetResourceId = connectToHub
  ? '/subscriptions/${hubSubscriptionId}/resourceGroups/${hubResourceGroupName}/providers/Microsoft.Network/virtualNetworks/${hubVnetName}'
  : ''
var useFirewall = connectToHub && !empty(firewallIP)
var reservedSubnetNames = [
  'AzureFirewallSubnet'
  'AzureFirewallManagementSubnet'
  'AzureBastionSubnet'
  'GatewaySubnet'
  'RouteServerSubnet'
]
var defaultNsgSubnetNames = map(filter(vnetSpokeSubnets, subnet => !contains(concat(reservedSubnetNames, [aksSubnetName, privateEndpointSubnetName], deployApplicationGateway ? [appgwsubnetName] : []), subnet.name)), subnet => subnet.name)
var deployDefaultNsg = !empty(defaultNsgSubnetNames)
var deployPrivateEndpointNsg = contains(map(vnetSpokeSubnets, subnet => subnet.name), privateEndpointSubnetName)

// Create Resource Group
module rg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: '${rgName}-deployment'
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

// Create AKS NSG (empty rules)
module nsgAKS 'br/public:avm/res/network/network-security-group:0.5.4' = {
  scope: resourceGroup(rgName)
  name: '${nsgAKSName}-deployment'
  params: {
    name: nsgAKSName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
  }
  dependsOn: [rg]
}

module nsgPrivateEndpoint 'br/public:avm/res/network/network-security-group:0.5.4' = if (deployPrivateEndpointNsg) {
  scope: resourceGroup(rgName)
  name: '${nsgPrivateEndpointName}-deployment'
  params: {
    name: nsgPrivateEndpointName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
    securityRules: empty(privateEndpointAllowedSourcePrefixes) ? [] : [
      {
        name: 'Allow-PrivateEndpoint-Clients'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['443', '445']
          sourceAddressPrefixes: privateEndpointAllowedSourcePrefixes
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Deny-Other-VNet-Inbound'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Deny'
          priority: 4000
          direction: 'Inbound'
        }
      }
    ]
  }
  dependsOn: [rg]
}

module nsgDefault 'br/public:avm/res/network/network-security-group:0.5.4' = if (deployDefaultNsg) {
  scope: resourceGroup(rgName)
  name: '${nsgDefaultName}-deployment'
  params: {
    name: nsgDefaultName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
  }
  dependsOn: [rg]
}

// Create App Gateway NSG with required rules
module nsgAppGw 'br/public:avm/res/network/network-security-group:0.5.4' = if (deployApplicationGateway) {
  scope: resourceGroup(rgName)
  name: '${nsgappgwName}-deployment'
  params: {
    name: nsgappgwName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowControlPlaneV1SKU'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65503-65534'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowControlPlaneV2SKU'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 111
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHealthProbes'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
    ]
  }
  dependsOn: [rg]
}

// Create AKS Route Table with route to firewall plus VnetLocal overrides
// so intra-VNet, AKS service and pod traffic stay local instead of transiting the firewall.
var vnetLocalRoutes = [for (cidr, i) in vnetSpokeAddressPrefixes: {
  name: 'vnet-to-vnet-${i}'
  properties: {
    nextHopType: 'VnetLocal'
    addressPrefix: cidr
  }
}]

var serviceCidrRoute = aksServiceCidr != null ? [
  {
    name: 'aksservice-to-aksservice'
    properties: {
      nextHopType: 'None'
      addressPrefix: aksServiceCidr!
    }
  }
] : []

var podCidrRoute = aksPodCidr != null ? [
  {
    name: 'pod-to-pod'
    properties: {
      nextHopType: 'None'
      addressPrefix: aksPodCidr!
    }
  }
] : []

var aksRoutes = useFirewall ? concat(
  [
    {
      name: 'aks-to-internet'
      properties: {
        nextHopType: 'VirtualAppliance'
        nextHopIpAddress: firewallIP
        addressPrefix: '0.0.0.0/0'
      }
    }
  ],
  vnetLocalRoutes,
  serviceCidrRoute,
  podCidrRoute
) : []

module routetable 'br/public:avm/res/network/route-table:0.5.0' = {
  scope: resourceGroup(rgName)
  name: '${rtAKSSubnetname}-deployment'
  params: {
    name: rtAKSSubnetname
    location: location
    tags: tags
    routes: aksRoutes
  }
  dependsOn: [rg]
}

// Create App Gateway Route Table
module appgwroutetable 'br/public:avm/res/network/route-table:0.5.0' = if (deployApplicationGateway) {
  scope: resourceGroup(rgName)
  name: '${appgwroutetableName}-deployment'
  params: {
    name: appgwroutetableName
    location: location
    tags: tags
  }
  dependsOn: [rg]
}

var configuredSubnets = map(vnetSpokeSubnets, subnet => union(subnet, subnet.name == aksSubnetName ? {
  networkSecurityGroupResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/networkSecurityGroups', nsgAKSName)
  routeTableResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/routeTables', rtAKSSubnetname)
} : deployApplicationGateway && subnet.name == appgwsubnetName ? {
  networkSecurityGroupResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/networkSecurityGroups', nsgappgwName)
  routeTableResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/routeTables', appgwroutetableName)
} : subnet.name == privateEndpointSubnetName ? {
  networkSecurityGroupResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/networkSecurityGroups', nsgPrivateEndpointName)
} : contains(defaultNsgSubnetNames, subnet.name) ? {
  networkSecurityGroupResourceId: resourceId(subscription().subscriptionId, rgName, 'Microsoft.Network/networkSecurityGroups', nsgDefaultName)
} : {}))

// Configure associations on every deployment so a rerun does not detach them.
module vnetSpoke 'br/public:avm/res/network/virtual-network:0.10.2' = {
  scope: resourceGroup(rgName)
  name: '${vnteSpokeName}-deployment'
  params: {
    name: vnteSpokeName
    location: location
    addressPrefixes: vnetSpokeAddressPrefixes
    dnsServers: dhcpOptions.?dnsServers ?? []
    subnets: configuredSubnets
    tags: tags
    diagnosticSettings: diagnosticSettings
    peerings: connectToHub ? [
      {
        name: '${vnteSpokeName}-to-${hubVnetName}'
        remoteVirtualNetworkResourceId: hubVnetResourceId
        allowForwardedTraffic: useFirewall
        allowVirtualNetworkAccess: true
        remotePeeringEnabled: createHubPeering
        remotePeeringName: '${hubVnetName}-to-${vnteSpokeName}'
        remotePeeringAllowForwardedTraffic: useFirewall
        remotePeeringAllowVirtualNetworkAccess: true
      }
    ] : []
  }
  dependsOn: [
    rg
    nsgAKS
    nsgAppGw
    nsgPrivateEndpoint
    nsgDefault
    routetable
    appgwroutetable
  ]
}

// Create Public IP for Application Gateway
module publicipappgw 'br/public:avm/res/network/public-ip-address:0.13.0' = if (deployApplicationGateway) {
  scope: resourceGroup(rgName)
  name: '${appgwpipName}-deployment'
  params: {
    name: appgwpipName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
    availabilityZones: availabilityZones
    publicIPAllocationMethod: 'Static'
    skuName: 'Standard'
    skuTier: 'Regional'
  }
  dependsOn: [rg]
}

// Application Gateway
var appgwResourceId = '/subscriptions/${subscription().subscriptionId}/resourceGroups/${rgName}/providers/Microsoft.Network/applicationGateways/${appgwName}'

module appgw 'br/public:avm/res/network/application-gateway:0.10.0' = if (deployApplicationGateway) {
  scope: resourceGroup(rgName)
  name: '${appgwName}-deployment'
  params: {
    name: appgwName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
    sku: 'Standard_v2'
    availabilityZones: availabilityZones
    autoscaleMinCapacity: int(appgwAutoScale.minCapacity)
    autoscaleMaxCapacity: int(appgwAutoScale.maxCapacity)
    gatewayIPConfigurations: [
      {
        name: 'appGateway-Ip-Config'
        properties: {
          subnet: {
            id: '${vnetSpoke.outputs.resourceId}/subnets/${appgwsubnetName}'
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: publicipappgw!.outputs.resourceId
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'appGatewayFrontendPort'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'appGatewayBackendPool'
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettings'
        properties: {
          cookieBasedAffinity: 'Disabled'
          path: '/'
          port: 80
          protocol: 'Http'
          requestTimeout: 60
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: '${appgwResourceId}/frontendIPConfigurations/appGatewayFrontendIP'
          }
          frontendPort: {
            id: '${appgwResourceId}/frontendPorts/appGatewayFrontendPort'
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'appGatewayRule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: '${appgwResourceId}/httpListeners/appGatewayHttpListener'
          }
          backendAddressPool: {
            id: '${appgwResourceId}/backendAddressPools/appGatewayBackendPool'
          }
          backendHttpSettings: {
            id: '${appgwResourceId}/backendHttpSettingsCollection/appGatewayBackendHttpSettings'
          }
        }
      }
    ]
  }
}

output vnetResourceId string = vnetSpoke.outputs.resourceId
