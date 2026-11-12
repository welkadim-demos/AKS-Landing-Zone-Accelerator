targetScope = 'subscription'

param rgName string
param location string = deployment().location
@description('Create PostgreSQL and Managed Redis zones for optional database deployments.')
param deployDatabaseZones bool = true
@description('Create the Container Registry zone. Disable when ACR is not deployed.')
param deployACRZone bool = true
@description('Create the Key Vault zone. Disable when Key Vault is not deployed.')
param deployKeyVaultZone bool = true
@description('Storage services to create private DNS zones for. Keep in sync with the supporting stage storagePrivateEndpointServices; dfs is only needed for hierarchical namespace.')
@allowed(['blob', 'dfs', 'file', 'queue', 'table'])
param storageServices string[] = ['blob', 'dfs', 'file', 'queue', 'table']
@description('Optional. Tags applied to the resource group and zones.')
param tags object = {}

var privateDNSZoneAKSSuffixes = {
  AzureCloud: '.azmk8s.io'
  AzureUSGovernment: '.cx.aks.containerservice.azure.us'
  AzureChinaCloud: '.cx.prod.service.azk8s.cn'
  AzureGermanCloud: '' //TODO: what is the correct value here?
}

module rg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: '${rgName}-deployment'
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

module privatednsACRZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (deployACRZone) {
  name: 'privatednsACRZone'
  scope: resourceGroup(rgName)
  params: {
    name: 'privatelink${environment().suffixes.acrLoginServer}'
    tags: tags
  }
  dependsOn: [rg]
}

module privatednsvalutZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (deployKeyVaultZone) {
  name: 'privatednsvalutZone'
  scope: resourceGroup(rgName)
  params: {
    name: 'privatelink.vaultcore.azure.net'
    tags: tags
  }
  dependsOn: [rg]
}

module privatednsStorageAccountZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = [for service in storageServices: {
  name: service == 'file' ? 'privatednsSAZone' : 'privatednsSAZone-${service}'
  scope: resourceGroup(rgName)
  params: {
    name: 'privatelink.${service}.${environment().suffixes.storage}'
    tags: tags
  }
  dependsOn: [rg]
}]

module privatednsAKSZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = {
  name: 'privatednsaksZone'
  scope: resourceGroup(rgName)
  params: {
    name: 'privatelink.${toLower(location)}${privateDNSZoneAKSSuffixes[environment().name]}'
    tags: tags
  }
  dependsOn: [rg]
}

module privatednsPostgreSQLZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (deployDatabaseZones) {
  name: 'privatednsPostgreSQLZone'
  scope: resourceGroup(rgName)
  params: {
    name: 'privatelink.postgres.database.azure.com'
    tags: tags
  }
  dependsOn: [rg]
}

module privatednsManagedRedisZone 'br/public:avm/res/network/private-dns-zone:0.8.1' = if (deployDatabaseZones) {
  name: 'privatednsManagedRedisZone'
  scope: resourceGroup(rgName)
  params: {
    name: 'privatelink.redis.azure.net'
    tags: tags
  }
  dependsOn: [rg]
}



