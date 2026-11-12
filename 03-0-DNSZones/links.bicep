targetScope = 'subscription'

param rgName string
param location string = deployment().location

@description('Existing VNets to link. Empty means no links. VNets may be in other subscriptions.')
param virtualNetworkResourceIds string[] = []

@description('Existing zones to link. Add database zones only when those workloads are deployed.')
param privateDNSZoneNames string[]?
@description('Storage services whose zones are linked. Keep in sync with the DNS zone stage.')
@allowed(['blob', 'dfs', 'file', 'queue', 'table'])
param storageServices string[] = ['blob', 'dfs', 'file', 'queue', 'table']
@description('Link the Container Registry zone. Disable when ACR is not deployed.')
param linkACRZone bool = true
@description('Link the Key Vault zone. Disable when Key Vault is not deployed.')
param linkKeyVaultZone bool = true

var acrZoneName = 'privatelink${environment().suffixes.acrLoginServer}'
var keyVaultZoneName = 'privatelink.vaultcore.azure.net'

var storageZoneNames = map(storageServices, service => 'privatelink.${service}.${environment().suffixes.storage}')

var zoneNames = privateDNSZoneNames ?? filter(concat([
  acrZoneName
  keyVaultZoneName
  'privatelink.${toLower(location)}${privateDNSZoneAKSSuffixes[environment().name]}'
], storageZoneNames), zoneName => (linkACRZone || zoneName != acrZoneName) && (linkKeyVaultZone || zoneName != keyVaultZoneName))

var privateDNSZoneAKSSuffixes = {
  AzureCloud: '.azmk8s.io'
  AzureUSGovernment: '.cx.aks.containerservice.azure.us'
  AzureChinaCloud: '.cx.prod.service.azk8s.cn'
  AzureGermanCloud: ''
}

var links = flatten(map(zoneNames, zoneName => map(virtualNetworkResourceIds, vnetId => {
  zoneName: zoneName
  vnetId: vnetId
})))

module zoneLinks '../modules/vnet/privatednslink.bicep' = [for link in links: {
  name: 'dns-link-${uniqueString(toLower(link.zoneName), toLower(link.vnetId))}'
  scope: resourceGroup(rgName)
  params: {
    privateDNSZoneName: link.zoneName
    vnetName: last(split(link.vnetId, '/'))
    vnetId: link.vnetId
  }
}]
