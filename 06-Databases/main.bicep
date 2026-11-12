targetScope = 'resourceGroup'

// =============================================================================
// 06 - Databases (PostgreSQL Flexible Server + Azure Managed Redis)
// Uses Azure Verified Modules (AVM):
//   - br/public:avm/res/db-for-postgre-sql/flexible-server:0.16.1
//   - br/public:avm/res/cache/redis-enterprise:0.5.1
//
// Re-uses the existing spoke VNet/subnets and existing private DNS zones.
// Does NOT create the VNet, subnets, NSGs, or private DNS zones.
// =============================================================================

// ---------------------------------------------------------------------------
// Common parameters
// ---------------------------------------------------------------------------
param location string = resourceGroup().location

@description('Name of the existing spoke VNet that holds the data + service-PE subnets.')
param spokeVnetName string

@description('Full ARM resource ID of the existing private DNS zone for PostgreSQL flexible server.')
param postgresPrivateDnsZoneResourceId string

@description('Full ARM resource ID of the existing private DNS zone for Azure Managed Redis / Redis Enterprise.')
param redisPrivateDnsZoneResourceId string

// ---------------------------------------------------------------------------
// PostgreSQL parameters
// ---------------------------------------------------------------------------
@description('PostgreSQL flexible server name.')
param pgServerName string

@description('Name of the delegated subnet for PostgreSQL flexible server.')
param pgDataSubnetName string = 'datasubnet'

@description('Compute SKU name (e.g. Standard_D2ds_v5, Standard_D4ds_v5).')
param pgSkuName string = 'Standard_D2ds_v5'

@allowed([
  'Burstable'
  'GeneralPurpose'
  'MemoryOptimized'
])
param pgSkuTier string = 'GeneralPurpose'

@description('PostgreSQL major version.')
@allowed([
  '11'
  '12'
  '13'
  '14'
  '15'
  '16'
  '17'
  '18'
])
param pgVersion string = '13'

@description('PostgreSQL administrator login.')
param pgAdministratorLogin string

@description('PostgreSQL administrator login password.')
@secure()
param pgAdministratorLoginPassword string

@description('Primary availability zone (-1 for no preference, 1/2/3).')
@allowed([
  -1
  1
  2
  3
])
param pgAvailabilityZone int = 1

@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param pgHighAvailability string = 'Disabled'

@description('Standby availability zone (-1 for no preference, 1/2/3). Only used when HA is not Disabled.')
@allowed([
  -1
  1
  2
  3
])
param pgHighAvailabilityZone int = -1

@minValue(7)
@maxValue(35)
param pgBackupRetentionDays int = 7

@allowed([
  'Enabled'
  'Disabled'
])
param pgGeoRedundantBackup string = 'Disabled'

@minValue(32)
param pgStorageSizeGB int = 256

@allowed([
  'P1'
  'P2'
  'P3'
  'P4'
  'P6'
  'P10'
  'P15'
  'P20'
  'P30'
  'P40'
  'P50'
  'P60'
  'P70'
  'P80'
])
param pgStorageTier string = 'P15'

// ---------------------------------------------------------------------------
// Redis (Azure Managed Redis / Redis Enterprise) parameters
// ---------------------------------------------------------------------------
@description('Name of the Redis Enterprise cluster.')
param redisClusterName string

@description('Redis Enterprise SKU (e.g. Balanced_B3, Balanced_B10, MemoryOptimized_M10).')
param redisSkuName string = 'Balanced_B3'

@description('Subnet used for the private endpoint (typically "servicespe").')
param redisPeSubnetName string = 'servicespe'

@description('Name of the private endpoint resource for the Redis cluster.')
param redisPrivateEndpointName string

@allowed([
  'Enabled'
  'Disabled'
])
param redisHighAvailability string = 'Enabled'

@allowed([
  'EnterpriseCluster'
  'NoCluster'
  'OSSCluster'
])
param redisClusteringPolicy string = 'OSSCluster'

@allowed([
  'AllKeysLFU'
  'AllKeysLRU'
  'AllKeysRandom'
  'NoEviction'
  'VolatileLFU'
  'VolatileLRU'
  'VolatileRandom'
  'VolatileTTL'
])
param redisEvictionPolicy string = 'NoEviction'

@allowed([
  'Encrypted'
  'Plaintext'
])
param redisClientProtocol string = 'Encrypted'

@allowed([
  'Enabled'
  'Disabled'
])
param redisAccessKeysAuthentication string = 'Enabled'

@description('Optional. Resource ID of a Log Analytics workspace. When set, diagnostic settings are sent to it for PostgreSQL and Redis.')
param logAnalyticsWorkspaceResourceId string = ''

var diagnosticSettings = empty(logAnalyticsWorkspaceResourceId) ? [] : [
  {
    name: 'send-to-log-analytics'
    workspaceResourceId: logAnalyticsWorkspaceResourceId
  }
]

// ---------------------------------------------------------------------------
// Existing resources (must already exist - this template does not create them)
// ---------------------------------------------------------------------------
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: spokeVnetName
}

var dataSubnetId = '${spokeVnet.id}/subnets/${pgDataSubnetName}'
var redisPeSubnetId = '${spokeVnet.id}/subnets/${redisPeSubnetName}'

// ---------------------------------------------------------------------------
// PostgreSQL Flexible Server (VNet-injected, private DNS integrated)
// ---------------------------------------------------------------------------
module postgresqlFlexibleServer 'br/public:avm/res/db-for-postgre-sql/flexible-server:0.16.1' = {
  name: '${pgServerName}-deployment'
  params: {
    name: pgServerName
    location: location
    availabilityZone: pgAvailabilityZone
    skuName: pgSkuName
    tier: pgSkuTier
    version: pgVersion
    administratorLogin: pgAdministratorLogin
    administratorLoginPassword: pgAdministratorLoginPassword
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    delegatedSubnetResourceId: dataSubnetId
    privateDnsZoneArmResourceId: postgresPrivateDnsZoneResourceId
    highAvailability: pgHighAvailability
    highAvailabilityZone: pgHighAvailability == 'Disabled' ? -1 : pgHighAvailabilityZone
    backupRetentionDays: pgBackupRetentionDays
    geoRedundantBackup: pgGeoRedundantBackup
    storageSizeGB: pgStorageSizeGB
    storageTier: pgStorageTier
    enableAdvancedThreatProtection: false
    diagnosticSettings: diagnosticSettings
  }
}

// ---------------------------------------------------------------------------
// Azure Managed Redis (Redis Enterprise) + private endpoint into the spoke
// ---------------------------------------------------------------------------
module redisEnterprise 'br/public:avm/res/cache/redis-enterprise:0.5.1' = {
  name: '${redisClusterName}-deployment'
  params: {
    name: redisClusterName
    location: location
    skuName: redisSkuName
    highAvailability: redisHighAvailability
    publicNetworkAccess: 'Disabled'
    diagnosticSettings: diagnosticSettings
    database: {
      clusteringPolicy: redisClusteringPolicy
      evictionPolicy: redisEvictionPolicy
      clientProtocol: redisClientProtocol
      accessKeysAuthentication: redisAccessKeysAuthentication
      persistence: {
        type: 'disabled'
      }
    }
    privateEndpoints: [
      {
        name: redisPrivateEndpointName
        subnetResourceId: redisPeSubnetId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: redisPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output postgresqlFqdn string = postgresqlFlexibleServer.outputs.?fqdn ?? ''
output postgresqlResourceId string = postgresqlFlexibleServer.outputs.resourceId
output redisHostName string = redisEnterprise.outputs.hostName
output redisResourceId string = redisEnterprise.outputs.resourceId
