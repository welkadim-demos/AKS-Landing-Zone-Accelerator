using '../../../03-Network-LZ/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')
param deployApplicationGateway = true

param rgName = 'rg-spoke-dev-uksouth-01'
param vnteSpokeName = 'vnet-spoke-dev-uksouth-01'
param vnetSpokeAddressPrefixes = ['10.1.0.0/16']
param vnetSpokeSubnets = [
  {
    name: 'default'
    addressPrefix: '10.1.0.0/24'
  }
  {
    name: 'AKS'
    addressPrefix: '10.1.1.0/24'
  }
  {
    name: 'AppGWSubnet'
    addressPrefix: '10.1.2.0/24'
  }
  {
    name: 'vmsubnet'
    addressPrefix: '10.1.3.0/24'
  }
  {
    name: 'servicespe'
    addressPrefix: '10.1.4.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
]
//param dhcpOptions = {
  // dnsServers: ['10.0.1.4'] // firewall private IP address if it is DNS server
//}
param nsgAKSName = 'nsg-aks-dev-uksouth-01'
param rtAKSSubnetname = 'rt-aks-dev-uksouth-01'
param aksSubnetName = 'AKS'
param connectToHub = true
param firewallIP = '10.0.1.4'
param hubVnetName = 'vnet-hub-dev-uksouth-01'
param hubSubscriptionId = readEnvironmentVariable('HUB_SUBSCRIPTION_ID')
param hubResourceGroupName = 'rg-hub-dev-uksouth-01'
param appgwpipName = 'pip-agw-dev-uksouth-01'
param appgwsubnetName = 'AppGWSubnet'
param appgwName = 'agw-dev-uksouth-01'
param availabilityZones = []
param appgwAutoScale = {
  minCapacity: 1
  maxCapacity: 2
}
param nsgappgwName = 'nsg-agw-dev-uksouth-01'
param appgwroutetableName = 'rt-agw-dev-uksouth-01'
