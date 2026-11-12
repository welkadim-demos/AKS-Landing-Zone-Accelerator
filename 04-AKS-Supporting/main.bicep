targetScope = 'subscription'

param rgName string
param location string = deployment().location
param deployACR bool = true
param deployKeyVault bool = true
param acrName string = 'eslzacr${uniqueString('acrvws', utcNow('u'))}'
param keyvaultName string = 'eslz-kv-${uniqueString('acrvws', utcNow('u'))}'
param enableAKVPurgeProtection bool = false
param storageAccountName string = 'eslzsa${uniqueString('aks', utcNow('u'))}'
@description('Storage account names to deploy. When omitted, deploy storageAccountName only.')
@minLength(1)
param storageAccountNames string[]?
@description('Storage services that get a private endpoint per account. Static website hosting (web) is not supported. Keep the DNS zone stage storageServices in sync.')
@allowed(['blob', 'dfs', 'file', 'queue', 'table'])
param storagePrivateEndpointServices string[] = ['file']
@allowed(['Enabled', 'Disabled', 'SecuredByPerimeter'])
param storagePublicNetworkAccess string?
param storageAccountType string
@description('Allow account-key authentication. Disabled by default so access uses Microsoft Entra ID; Azure Files SMB mounts that rely on account keys require true.')
param storageAllowSharedKeyAccess bool = false
@description('Optional. Tags applied to all resources.')
param tags object = {}
@description('Optional. Resource ID of a Log Analytics workspace. When set, diagnostic settings are sent to it for every supported resource.')
param logAnalyticsWorkspaceResourceId string = ''

var diagnosticSettings = empty(logAnalyticsWorkspaceResourceId) ? [] : [
  {
    name: 'send-to-log-analytics'
    workspaceResourceId: logAnalyticsWorkspaceResourceId
  }
]
var serviceDiagnosticSettings = empty(diagnosticSettings) ? {} : {
  diagnosticSettings: diagnosticSettings
}
param rgSpokevnetName string
param vnetSpokeName string
param serviceepSubnetName string
param keyVaultPrivateEndpointName string
param acrPrivateEndpointName string
param saPrivateEndpointName string
param privatednszonesSubscriptionId string = subscription().subscriptionId
param privatednszonesRGName string = rgName
param privateDNSZoneACRName string = 'privatelink${environment().suffixes.acrLoginServer}'
param privateDNSZoneKVName string = 'privatelink.vaultcore.azure.net'
param privateDNSZoneSAName string = 'privatelink.file.${environment().suffixes.storage}'
param aksIdentityName string = 'aksIdentity'

// Construct private DNS zone resource IDs
var privateDNSZoneACRId = '/subscriptions/${privatednszonesSubscriptionId}/resourceGroups/${privatednszonesRGName}/providers/Microsoft.Network/privateDnsZones/${privateDNSZoneACRName}'
var privateDNSZoneKVId = '/subscriptions/${privatednszonesSubscriptionId}/resourceGroups/${privatednszonesRGName}/providers/Microsoft.Network/privateDnsZones/${privateDNSZoneKVName}'
var privateDNSZoneSAId = '/subscriptions/${privatednszonesSubscriptionId}/resourceGroups/${privatednszonesRGName}/providers/Microsoft.Network/privateDnsZones/${privateDNSZoneSAName}'
var accountNames = storageAccountNames ?? [storageAccountName]

resource servicesSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  scope: resourceGroup(rgSpokevnetName)
  name: '${vnetSpokeName}/${serviceepSubnetName}'
}

module rg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: rgName
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

module acr 'br/public:avm/res/container-registry/registry:0.13.1' = if (deployACR) {
  scope: resourceGroup(rgName)
  name: acrName
  params: {
    name: acrName
    location: location
    tags: tags
    acrSku: 'Premium'
    acrAdminUserEnabled: false
    diagnosticSettings: diagnosticSettings
    privateEndpoints: [
      {
        name: acrPrivateEndpointName
        subnetResourceId: servicesSubnet.id
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDNSZoneACRId
            }
          ]
        }
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

module keyvault 'br/public:avm/res/key-vault/vault:0.14.2' = if (deployKeyVault) {
  scope: resourceGroup(rgName)
  name: keyvaultName
  params: {
    name: keyvaultName
    location: location
    tags: tags
    diagnosticSettings: diagnosticSettings
    sku: 'standard'
    enableRbacAuthorization: false
    enableVaultForDiskEncryption: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: enableAKVPurgeProtection
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    privateEndpoints: [
      {
        name: keyVaultPrivateEndpointName
        subnetResourceId: servicesSubnet.id
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: privateDNSZoneKVId
            }
          ]
        }
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

module storage 'br/public:avm/res/storage/storage-account:0.33.1' = [for (accountName, i) in accountNames: {
  scope: resourceGroup(rgName)
  name: accountName
  params: {
    name: accountName
    location: location
    tags: tags
    skuName: storageAccountType
    kind: 'StorageV2'
    publicNetworkAccess: storagePublicNetworkAccess
    allowSharedKeyAccess: storageAllowSharedKeyAccess
    defaultToOAuthAuthentication: true
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
    fileServices: union({
      shareDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
    }, serviceDiagnosticSettings)
    blobServices: union({
      containerDeleteRetentionPolicyEnabled: true
      containerDeleteRetentionPolicyDays: 7
      deleteRetentionPolicyEnabled: true
      deleteRetentionPolicyDays: 6
    }, serviceDiagnosticSettings)
    queueServices: serviceDiagnosticSettings
    tableServices: serviceDiagnosticSettings
    diagnosticSettings: diagnosticSettings
    privateEndpoints: [for service in storagePrivateEndpointServices: {
      name: i == 0 && service == 'file' ? saPrivateEndpointName : '${accountName}-${service}-pe'
      service: service
      subnetResourceId: servicesSubnet.id
      privateDnsZoneGroup: {
        privateDnsZoneGroupConfigs: [
          {
            privateDnsZoneResourceId: service == 'file'
              ? privateDNSZoneSAId
              : resourceId(privatednszonesSubscriptionId, privatednszonesRGName, 'Microsoft.Network/privateDnsZones', 'privatelink.${service}.${environment().suffixes.storage}')
          }
        ]
      }
    }]
  }
  dependsOn: [
    rg
  ]
}]

module aksIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  scope: resourceGroup(rgName)
  name: aksIdentityName
  params: {
    name: aksIdentityName
    location: location
    tags: tags
  }
  dependsOn: [
    rg
  ]
}

output acrName string? = deployACR ? acr!.outputs.name : null
output keyvaultName string? = deployKeyVault ? keyvault!.outputs.name : null
output storageAccountResourceIds array = [for (accountName, i) in accountNames: storage[i].outputs.resourceId]
