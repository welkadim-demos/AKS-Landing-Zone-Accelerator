using '../../../03-0-DNSZones/links.bicep'

param rgName = 'rg-private-dns-zones'
param location = 'swedencentral'
param virtualNetworkResourceIds = [
  readEnvironmentVariable('SPOKE_VNET_RESOURCE_ID')
]
param storageServices = ['blob', 'file']
param linkACRZone = false
param linkKeyVaultZone = false
