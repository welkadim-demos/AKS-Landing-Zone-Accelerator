targetScope = 'subscription'

param rgName string
param vnetSubnetname string
param vmsize string
param location string = deployment().location
@secure()
param adminUsername string
@secure()
param adminPassword string

resource subnetVM 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' existing = {
  scope: resourceGroup(rgName)
  name: vnetSubnetname
}

module jumbBox 'br/public:avm/res/compute/virtual-machine:0.22.3' = {
  scope: resourceGroup(rgName)
  name: 'jumbBox'
  params: {
    name: 'jumbBox'
    location: location
    osType: 'Windows'
    vmSize: vmsize
    availabilityZone: -1
    adminUsername: adminUsername
    adminPassword: adminPassword
    imageReference: {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2019-Datacenter'
      version: 'latest'
    }
    osDisk: {
      createOption: 'FromImage'
      managedDisk: {
        storageAccountType: 'Standard_LRS'
      }
    }
    nicConfigurations: [
      {
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: subnetVM.id
          }
        ]
      }
    ]
  }
}
