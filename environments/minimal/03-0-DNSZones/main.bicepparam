using '../../../03-0-DNSZones/main.bicep'

param rgName = 'rg-private-dns-zones'
param location = 'swedencentral'
param deployDatabaseZones = false
param storageServices = ['blob', 'file']
param deployACRZone = false
param deployKeyVaultZone = false
param tags = {
  environment: 'minimal'
  workload: 'aks-landing-zone'
}
