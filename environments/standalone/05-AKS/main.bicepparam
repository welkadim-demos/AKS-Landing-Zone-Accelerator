using '../../../05-AKS/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')

param rgName = 'rg-spoke-dev-uksouth-01'
param location = 'uksouth'
param aksIdentityName = 'aksdevIdentity'
param privateDNSZoneAKSName = ''
param privateDNSZoneAKSNameSubscriptionId = readEnvironmentVariable('DNS_SUBSCRIPTION_ID')
param privateDNSZoneAKSNameResourceGroup = 'rg-private-dns-zones'
param akslaworkspaceName = 'log-dev-uksouth-001'
param aksvnetName = 'vnet-spoke-dev-uksouth-01'
param vnetspokeRGName = 'rg-spoke-dev-uksouth-01'
param akssubnetName = 'AKS'
param aksAppGatewayName = 'agw-dev-uksouth-01'
param rtaksName = 'rt-aks-dev-uksouth-01'
param aksClusterName = 'aks-dev-uksouth-001'
param kubernetesVersion = readEnvironmentVariable('AKS_KUBERNETES_VERSION')
param aksadminGroupaccessprincipalId = readEnvironmentVariable('AKS_ADMIN_GROUP_ID')
param aksusersgroupaccessprincipalId = readEnvironmentVariable('AKS_USERS_GROUP_ID')
param autoScalingProfile = {}
param aksNetworkPlugin = 'azure'
param aksNetworkPluginMode = 'overlay'
param aksPodCidr = '172.20.0.0/16'
param aksServiceCidr = '192.168.100.0/24'
param aksDnsServiceIP = '192.168.100.10'
param aksNetworkPolicy = 'azure'
param aksOutboundType = 'loadBalancer'
param aksEnableWebRoutingAddOn = false
param aksSystemPoolVMSize = 'Standard_D8ds_v5'
param additionalNodePools = [
  {
    name: 'userpool'
    count: 3
    enableAutoScaling: true
    minCount: 1
    maxCount: 3
    mode: 'User'
    osDiskSizeGB: 60
    vmSize: 'Standard_D8ds_v5'
    scaleSetPriority: 'Regular'
    scaleSetEvictionPolicy: 'Delete'
    type: 'VirtualMachineScaleSets'
    enableEncryptionAtHost: true
  }
  {
    name: 'rmqnp'
    count: 3
    enableAutoScaling: false
    mode: 'User'
    osDiskSizeGB: 128
    vmSize: 'Standard_D8ds_v5'
    type: 'VirtualMachineScaleSets'
    enableEncryptionAtHost: true
    nodeLabels: {
      workload: 'rabbitmq'
    }
    nodeTaints: [
      'workload=rabbitmq:NoSchedule'
    ]
  }
]
param acrName = 'welkacraksdev001'
param keyvaultName = 'kv-aks-dev-uksouth-001'
