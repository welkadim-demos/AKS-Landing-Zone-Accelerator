using '../../../02-Network-Hub/main.bicep'

param logAnalyticsWorkspaceResourceId = readEnvironmentVariable('LOG_ANALYTICS_WORKSPACE_ID', '')

param deployFirewall = true
param deployBastion = true
param deployVMRouteTable = true
param rgName = 'rg-hub-dev-uksouth-02'
param vnetHubName = 'vnet-hub-dev-uksouth-02'
param hubVnetAddressPrefixes = [
  '10.0.0.0/16'
]
param hubSubnets = [
  {
    name: 'default'
    addressPrefix: '10.0.0.0/24'
  }
  {
    name: 'AzureFirewallSubnet'
    addressPrefix: '10.0.1.0/26'
  }
  {
    name: 'AzureFirewallManagementSubnet'
    addressPrefix: '10.0.4.0/26'
  }
  {
    name: 'AzureBastionSubnet'
    addressPrefix: '10.0.2.0/26'
  }
  {
    name: 'vmsubnet'
    addressPrefix: '10.0.3.0/24'
  }
]

param firewallPolicyName = 'afwp-hub-uksouth-01'
param threatIntelMode = 'Deny'
param firewallPolicyTier = 'Standard'
param azfwName = 'azfw-hub-dev-uksouth-01'
param rtVMSubnetname = 'rt-vm-subnet'
param aksIpGroupName = 'ipg-aks-subnets-dev'
param aksSubnetPrefixes = [
  '172.17.1.0/24'
]

param applicationRuleCollectionGroupName = 'DefaultApplicationRuleCollection'
param applicationRuleCollectionGroupPriority = 300
param networkRuleCollectionGroupName = 'DefaultNetworkRuleCollectionGroup'
param networkRuleCollectionGroupPriority = 200
param applicationRuleCollections = [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Allow-ifconfig'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              'ifconfig.co'
              'api.snapcraft.io'
              'jsonip.com'
              'kubernaut.io'
              'motd.ubuntu.com'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: []
            httpHeadersToInsert: []
          }
        ]
        name: 'Helper-tools'
        priority: 101
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Egress'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              '*.azmk8s.io'
              '*.blob.core.windows.net'
              'mcr.microsoft.com'
              '*.data.mcr.microsoft.com'
              'mcr-0001.mcr-msedge.net'
              'management.azure.com'
              'login.microsoftonline.com'
              'packages.microsoft.com'
              'acs-mirror.azureedge.net'
              'packages.aks.azure.com'
              'vault.azure.net'
              'data.policy.core.windows.net'
              'store.policy.core.windows.net'
              '*.opinsights.azure.com'
              '*.monitoring.azure.com'
              'dc.services.visualstudio.com'
              'global.handler.control.monitor.azure.com'
              '*.ingest.monitor.azure.com'
              '*.metrics.ingest.monitor.azure.com'
              '*.handler.control.monitor.azure.com'
              '*.dp.kubernetesconfiguration.azure.com'
              'arcmktplaceprod.azurecr.io'
              '*.data.azurecr.io'
              '*.ingestion.msftcloudes.com'
              '*.microsoftmetrics.com'
              'marketplaceapi.microsoft.com'
              '*.cloud.defender.microsoft.com'
              '*.in.applicationinsights.azure.com'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: []
            httpHeadersToInsert: []
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Registries'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              '*.azurecr.io'
              '*.gcr.io'
              '*.docker.io'
              'quay.io'
              '*.quay.io'
              '*.cloudfront.net'
              'production.cloudflare.docker.com'
              'ghcr.io'
              'pkg-containers.githubusercontent.com'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: []
            httpHeadersToInsert: []
          }
          {
            ruleType: 'ApplicationRule'
            name: 'Additional-Usefull-Address'
            protocols: [
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              'grafana.net'
              'grafana.com'
              'stats.grafana.org'
              'github.com'
              'charts.bitnami.com'
              'raw.githubusercontent.com'
              '*.letsencrypt.org'
              'usage.projectcalico.org'
              'vortex.data.microsoft.com'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: []
            httpHeadersToInsert: []
          }
          {
            ruleType: 'ApplicationRule'
            name: 'AKS-FQDN-TAG'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: [
              'AzureKubernetesService'
            ]
            webCategories: []
            targetFqdns: []
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: []
            httpHeadersToInsert: []
          }
        ]
        name: 'AKS-egress-application'
        priority: 102
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'ApplicationRule'
            name: 'Ubuntu-Updates'
            protocols: [
              {
                protocolType: 'Http'
                port: 80
              }
              {
                protocolType: 'Https'
                port: 443
              }
            ]
            fqdnTags: []
            webCategories: []
            targetFqdns: [
              'security.ubuntu.com'
              'azure.archive.ubuntu.com'
              'changelogs.ubuntu.com'
              'snapshot.ubuntu.com'
            ]
            targetUrls: []
            terminateTLS: false
            sourceAddresses: []
            destinationAddresses: []
            sourceIpGroups: []
            httpHeadersToInsert: []
          }
        ]
        name: 'AKS-os-updates'
        priority: 103
      }
    ]

param networkRuleCollections = [
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'NTP'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: []
            sourceIpGroups: []
            destinationAddresses: [
              '*'
            ]
            destinationIpGroups: []
            destinationFqdns: []
            destinationPorts: [
              '123'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'APITCP'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: []
            sourceIpGroups: []
            destinationAddresses: [
              '*'
            ]
            destinationIpGroups: []
            destinationFqdns: []
            destinationPorts: [
              '9000'
            ]
          }
          {
            ruleType: 'NetworkRule'
            name: 'APIUDP'
            ipProtocols: [
              'UDP'
            ]
            sourceAddresses: []
            sourceIpGroups: []
            destinationAddresses: [
              '*'
            ]
            destinationIpGroups: []
            destinationFqdns: []
            destinationPorts: [
              '1194'
            ]
          }
        ]
        name: 'AKS-egress'
        priority: 200
      }
      {
        ruleCollectionType: 'FirewallPolicyFilterRuleCollection'
        action: {
          type: 'Allow'
        }
        rules: [
          {
            ruleType: 'NetworkRule'
            name: 'AzureMonitor'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: []
            sourceIpGroups: []
            destinationAddresses: [
              'AzureMonitor'
            ]
            destinationIpGroups: []
            destinationFqdns: []
            destinationPorts: [
              '443'
            ]
          }
        ]
        name: 'AKS-monitoring'
        priority: 201
      }
    ]


param location = 'uksouth'
param availabilityZones = [
  1
  2
  3
]
