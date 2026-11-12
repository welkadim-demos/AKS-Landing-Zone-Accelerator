param principalId string
param roleGuid string
param pvtdnsAKSZoneName string

resource pvtdnsAKSZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: pvtdnsAKSZoneName
}

resource role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleGuid)
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleGuid)
  }
  scope: pvtdnsAKSZone
}
