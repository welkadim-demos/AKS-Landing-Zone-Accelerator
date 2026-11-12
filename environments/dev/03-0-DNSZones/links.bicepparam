using '../../../03-0-DNSZones/links.bicep'

param rgName = 'rg-private-dns-zones'
param location = 'uksouth'
param virtualNetworkResourceIds = [
  readEnvironmentVariable('SPOKE_VNET_RESOURCE_ID')
]
