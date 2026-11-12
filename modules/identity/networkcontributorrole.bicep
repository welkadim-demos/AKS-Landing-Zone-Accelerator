param principalId string
param roleGuid string
param vnetName string
@description('Optional. Scope the assignment to this subnet instead of the whole virtual network.')
param subnetName string = ''

resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = if (!empty(subnetName)) {
  parent: spokeVnet
  name: subnetName
}

resource vnet_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (empty(subnetName)) {
  name: guid(subscription().id, principalId, roleGuid)
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleGuid)
  }
  scope: spokeVnet
}

resource subnet_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(subnetName)) {
  name: guid(subscription().id, principalId, roleGuid, vnetName, subnetName)
  properties: {
    principalId: principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleGuid)
  }
  scope: subnet
}
