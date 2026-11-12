using '../../../05-AKS/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')
param enableACRIntegration = true
param enableKeyVaultIntegration = true
param aksSupportPlan = 'KubernetesOfficial'

param rgName = 'rg-aks-dev-uksouth-001'
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
param kubernetesVersion = '1.28.9'
param skuName = 'Base'
param skuTier = 'Standard'
param aksadminGroupaccessprincipalId = readEnvironmentVariable('AKS_ADMIN_GROUP_ID')
param aksusersgroupaccessprincipalId = readEnvironmentVariable('AKS_USERS_GROUP_ID')
param enableAzurePolicy = true
param enableOMSAgent = true
param enableIngressApplicationGateway = true
param availabilityZones = []
param enableAutoScaling = true
param enableWorkloadIdentity = true
param autoScalingProfile = {
  'balance-similar-node-groups': 'false'
  expander: 'random'
  'max-empty-bulk-delete': '10'
  'max-graceful-termination-sec': '600'
  'max-node-provision-time': '15m'
  'max-total-unready-percentage': '45'
  'new-pod-scale-up-delay': '0s'
  'ok-total-unready-count': '3'
  'scale-down-delay-after-add': '10m' 
  'scale-down-delay-after-delete': '10s'
  'scale-down-delay-after-failure': '3m' 
  'scale-down-unneeded-time': '10m'
  'scale-down-unready-time': '20m'
  'scale-down-utilization-threshold': '0.5'
  'scan-interval': '10s'
  'skip-nodes-with-local-storage': 'false'
  'skip-nodes-with-system-pods': 'true'
}
param aksNetworkPlugin = 'azure'
param aksNetworkPluginMode = 'overlay'
param aksPodCidr = '172.50.0.0/16'
param aksServiceCidr = '192.168.100.0/24'
param aksDnsServiceIP = '192.168.100.10'
param aksNetworkPolicy = 'calico'
param aksOutboundType = 'userDefinedRouting'

param aksSystemPoolVMSize = 'Standard_D4d_v4'
param aksSystemPoolNodesCount = 3
param additionalNodePools = [
  {
    name: 'userpool'
    count: 3
    enableAutoScaling: true
    minCount: 1
    maxCount: 3
    mode: 'User'
    osDiskSizeGB: 60
    vmSize: 'Standard_D4d_v4'
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
    vmSize: 'Standard_D4d_v4'
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
param keyvaultName = 'kv-aks-dev-uksouth-003'
