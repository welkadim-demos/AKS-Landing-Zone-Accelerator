using '../../../03-Network-LZ/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')

param rgName = 'rg-spoke-dev-swedencentral-01'
param location = 'swedencentral'
param vnteSpokeName = 'vnet-spoke-dev-swedencentral-01'
param vnetSpokeAddressPrefixes = ['172.17.0.0/16']
param vnetSpokeSubnets = [
  {
    name: 'AKS'
    addressPrefix: '172.17.1.0/24'
    defaultOutboundAccess: false
  }
  {
    name: 'servicespe'
    addressPrefix: '172.17.4.0/24'
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Enabled'
  }
]
param privateEndpointAllowedSourcePrefixes = ['172.17.1.0/24']
param tags = {
  environment: 'minimal'
  workload: 'aks-landing-zone'
}
param connectToHub = true
param hubSubscriptionId = readEnvironmentVariable('HUB_SUBSCRIPTION_ID')
param hubResourceGroupName = 'rg-hub-dev-swedencentral-02'
param hubVnetName = 'vnet-hub-dev-swedencentral-02'
param firewallIP = ''
param aksSubnetName = 'AKS'
param nsgAKSName = 'nsg-aks-dev-swedencentral-01'
param rtAKSSubnetname = 'rt-aks-dev-swedencentral-01'
param deployApplicationGateway = false
param appgwpipName = 'pip-appgw-dev-swedencentral-01'
param appgwsubnetName = ''
param appgwName = 'appgw-dev-swedencentral-01'
param availabilityZones = []
param appgwAutoScale = {
  minCapacity: 1
  maxCapacity: 2
}
param nsgappgwName = 'nsg-appgw-dev-swedencentral-01'
param appgwroutetableName = 'rt-appgw-dev-swedencentral-01'
