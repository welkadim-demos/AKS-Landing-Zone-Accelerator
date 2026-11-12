using '../../../02-Network-Hub/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')

param rgName = 'rg-hub-dev-swedencentral-02'
param location = 'swedencentral'
param vnetHubName = 'vnet-hub-dev-swedencentral-02'
param hubVnetAddressPrefixes = ['10.0.0.0/16']
param hubSubnets = [
  {
    name: 'default'
    addressPrefix: '10.0.0.0/24'
    defaultOutboundAccess: false
  }
]
param tags = {
  environment: 'minimal'
  workload: 'aks-landing-zone'
}
param deployFirewall = false
param deployBastion = false
param deployVMRouteTable = false

// Required legacy inputs are unused when firewall and VM routing are disabled.
param firewallPolicyName = 'afwp-hub-dev-swedencentral-02'
param threatIntelMode = 'Deny'
param firewallPolicyTier = 'Standard'
param applicationRuleCollectionGroupName = 'ApplicationRules'
param applicationRuleCollectionGroupPriority = 300
param applicationRuleCollections = []
param networkRuleCollectionGroupName = 'NetworkRules'
param networkRuleCollectionGroupPriority = 200
param networkRuleCollections = []
param azfwName = 'azfw-hub-dev-swedencentral-02'
param rtVMSubnetname = 'rt-vm-dev-swedencentral-02'
param aksIpGroupName = 'ipg-aks-dev-swedencentral-02'
param aksSubnetPrefixes = []
param availabilityZones = []
