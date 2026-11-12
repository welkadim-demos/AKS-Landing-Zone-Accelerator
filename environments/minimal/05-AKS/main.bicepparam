using '../../../05-AKS/main.bicep'

param rgName = 'rg-spoke-dev-swedencentral-01'
param location = 'swedencentral'
param aksIdentityName = 'aksdevIdentity'
param privateDNSZoneAKSName = ''
param privateDNSZoneAKSNameSubscriptionId = readEnvironmentVariable('DNS_SUBSCRIPTION_ID')
param privateDNSZoneAKSNameResourceGroup = 'rg-private-dns-zones'
param akslaworkspaceName = 'log-dev-swedencentral-001'
param aksvnetName = 'vnet-spoke-dev-swedencentral-01'
param vnetspokeRGName = 'rg-spoke-dev-swedencentral-01'
param akssubnetName = 'AKS'
param rtaksName = 'rt-aks-dev-swedencentral-01'
param aksAppGatewayName = ''
param aksClusterName = 'aks-dev-swedencentral-001'
param kubernetesVersion = '1.36.5'
param skuTier = 'Premium'
param aksSupportPlan = 'AKSLongTermSupport'
param aksadminGroupaccessprincipalId = readEnvironmentVariable('AKS_ADMIN_GROUP_ID')
param aksusersgroupaccessprincipalId = readEnvironmentVariable('AKS_USERS_GROUP_ID')
param enableIngressApplicationGateway = false
param aksEnableWebRoutingAddOn = false
param enableACRIntegration = false
param enableKeyVaultIntegration = false
param acrName = ''
param keyvaultName = ''
param autoScalingProfile = {}
param aksNetworkPlugin = 'azure'
param aksNetworkPluginMode = 'overlay'
param aksPodCidr = '172.20.0.0/16'
param aksServiceCidr = '192.168.100.0/24'
param aksDnsServiceIP = '192.168.100.10'
param aksNetworkDataplane = 'azure'
param aksNetworkPolicy = 'azure'
// Kubernetes version upgrades are manual; node OS images stay managed (NodeImage channel) inside the maintenance window.
param aksUpgradeChannel = 'none'
param aksNodeOSUpgradeChannel = 'NodeImage'
param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')
param tags = {
  environment: 'minimal'
  workload: 'aks-landing-zone'
}
param aksOutboundType = 'loadBalancer'
param availabilityZones = [2, 3]
param aksSystemPoolName = 'base'
param aksSystemPoolOSDiskSizeGB = 128
param aksSystemPoolOSDiskType = 'Ephemeral'
param aksSystemPoolVMSize = 'Standard_D16ads_v6'
param aksSystemPoolNodesCount = 3
param aksSystemPoolNodeMin = 3
param aksSystemPoolNodeMax = 3
// base (system + application), burst (Spot jobs) and burstmemory (temporary, retire after expiresOn).
// Burst pools scale to zero. To retire burstmemory, remove its entry and run
// az aks nodepool delete; incremental deployments do not delete pools.
param additionalNodePools = [
  {
    name: 'burst'
    count: 1
    enableAutoScaling: true
    minCount: 0
    maxCount: 1
    mode: 'User'
    osDiskSizeGB: 60
    osDiskType: 'Ephemeral'
    vmSize: 'Standard_D32ads_v6'
    scaleSetPriority: 'Spot'
    scaleSetEvictionPolicy: 'Delete'
    spotMaxPrice: -1
    nodeLabels: {
      'kubernetes.azure.com/scalesetpriority': 'spot'
      workload: 'burst'
    }
    nodeTaints: [
      'kubernetes.azure.com/scalesetpriority=spot:NoSchedule'
    ]
    type: 'VirtualMachineScaleSets'
    enableEncryptionAtHost: true
  }
  {
    name: 'burstmemory'
    count: 1
    enableAutoScaling: true
    minCount: 0
    maxCount: 1
    mode: 'User'
    osDiskSizeGB: 128
    osDiskType: 'Ephemeral'
    vmSize: 'Standard_E32ads_v6'
    type: 'VirtualMachineScaleSets'
    enableEncryptionAtHost: true
    nodeLabels: {
      workload: 'burst-memory'
    }
    nodeTaints: [
      'workload=burst-memory:NoSchedule'
    ]
    tags: {
      lifecycle: 'temporary'
      expiresOn: '2027-02-11'
    }
  }
]
