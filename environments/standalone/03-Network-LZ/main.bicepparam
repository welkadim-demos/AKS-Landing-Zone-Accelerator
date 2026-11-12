using '../../../03-Network-LZ/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')

param rgName = 'rg-spoke-dev-uksouth-01'
param vnteSpokeName = 'vnet-spoke-dev-uksouth-01'
param connectToHub = false
param vnetSpokeAddressPrefixes = ['172.17.0.0/16']
param vnetSpokeSubnets = [
  {
    name: 'vmsubnet'
    addressPrefix: '172.17.0.0/24'
  }
  {
    name: 'AKS'
    addressPrefix: '172.17.1.0/24'
  }
  {
    name: 'AppGWSubnet'
    addressPrefix: '172.17.3.0/24'
  }
  {
    name: 'servicespe'
    addressPrefix: '172.17.4.0/24'
    privateEndpointNetworkPolicies: 'Disabled'
  }
]
param aksSubnetName = 'AKS'
param nsgAKSName = 'nsg-aks-dev-uksouth-01'
param rtAKSSubnetname = 'rt-aks-dev-uksouth-01'
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
