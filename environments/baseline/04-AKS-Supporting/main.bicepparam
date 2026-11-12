using '../../../04-AKS-Supporting/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')
param deployACR = true
param deployKeyVault = true
param storagePrivateEndpointServices = ['file']
param storagePublicNetworkAccess = null

param rgName = 'rg-aks-dev-uksouth-001'
param location = 'uksouth'
param acrName = 'welkacraksdev001'
param keyvaultName = 'kv-aks-dev-uksouth-003'
param storageAccountName = 'welstaksdev001'
param storageAccountType = 'Standard_LRS'
param rgSpokevnetName = 'rg-spoke-dev-uksouth-01'
param vnetSpokeName = 'vnet-spoke-dev-uksouth-01'
param serviceepSubnetName = 'servicespe'
param keyVaultPrivateEndpointName = 'keyvault-pvt-ep'
param acrPrivateEndpointName = 'acr-pvt-ep'
param saPrivateEndpointName = 'sa-pvt-ep'
param privatednszonesSubscriptionId = readEnvironmentVariable('DNS_SUBSCRIPTION_ID')
param privatednszonesRGName = 'rg-private-dns-zones'
param aksIdentityName = 'aksdevIdentity'

