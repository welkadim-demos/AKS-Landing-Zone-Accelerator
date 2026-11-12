targetScope = 'subscription'

param vmVnetName string
param vmVNetSubnetName string
param rtVMSubnetName string
param rgName string

resource subnetVM 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  scope: resourceGroup(rgName)
  name: '${vmVnetName}/${vmVNetSubnetName}'
}

resource rtVM 'Microsoft.Network/routeTables@2024-05-01' existing ={
  scope: resourceGroup(rgName)
  name: rtVMSubnetName
}

// Update subnet to associate the route table - using native resource as there is no AVM module for single subnet updates
module updateUDR 'br/public:avm/res/network/virtual-network:0.10.2' = {
  scope: resourceGroup(rgName)
  name: 'updateUDR'
  params: {
    name: vmVnetName
    addressPrefixes: []
    subnets: [
      {
        name: vmVNetSubnetName
        addressPrefix: subnetVM.properties.addressPrefix
        routeTableResourceId: rtVM.id
      }
    ]
  }
}
