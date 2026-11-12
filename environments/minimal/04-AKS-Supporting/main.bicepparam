using '../../../04-AKS-Supporting/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')

param rgName = 'rg-spoke-dev-swedencentral-01'
param location = 'swedencentral'
param deployACR = false
param deployKeyVault = false
param storageAccountNames = [
  'staksminswc001'
  'staksminswc002'
]
param storageAccountType = 'Standard_ZRS'
param tags = {
  environment: 'minimal'
  workload: 'aks-landing-zone'
}
param storagePublicNetworkAccess = 'Disabled'
param storagePrivateEndpointServices = ['blob', 'file']
param rgSpokevnetName = 'rg-spoke-dev-swedencentral-01'
param vnetSpokeName = 'vnet-spoke-dev-swedencentral-01'
param serviceepSubnetName = 'servicespe'
param keyVaultPrivateEndpointName = ''
param acrPrivateEndpointName = ''
param saPrivateEndpointName = 'sa-pvt-ep'
param privatednszonesSubscriptionId = readEnvironmentVariable('DNS_SUBSCRIPTION_ID')
param privatednszonesRGName = 'rg-private-dns-zones'
param aksIdentityName = 'aksdevIdentity'
