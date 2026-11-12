param dnsZoneResourceId string 
param principalId string
param roleGuid string

resource dnsZone 'Microsoft.Network/dnsZones@2018-05-01' existing =  {
  name: dnsZoneResourceId
}

resource role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleGuid)
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleGuid)
  }
  scope: dnsZone
}

