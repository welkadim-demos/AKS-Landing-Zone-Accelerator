param principalId string
param roleGuid string
param rtName string

resource rt 'Microsoft.Network/routeTables@2024-05-01' existing = {
  name: rtName
}

resource role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, principalId, roleGuid, rtName)
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleGuid)
  }
  scope: rt
}
