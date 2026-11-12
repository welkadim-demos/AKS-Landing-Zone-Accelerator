targetScope = 'subscription'

@description('Resource group that holds the shared Log Analytics workspace.')
param rgName string
param location string = deployment().location
@description('Name of the shared Log Analytics workspace that receives diagnostic settings from every stage.')
param workspaceName string
@minValue(30)
@maxValue(730)
param dataRetentionInDays int = 30
@description('Daily ingestion cap in GB (supports decimals, e.g. 5). Use -1 for no cap.')
param dailyQuotaGb string = '-1'
@description('Send the subscription Activity Log to the workspace.')
param enableActivityLogDiagnostics bool = true
@description('Optional. Tags applied to all resources.')
param tags object = {}

module rg 'br/public:avm/res/resources/resource-group:0.4.4' = {
  name: '${rgName}-deployment'
  params: {
    name: rgName
    location: location
    tags: tags
  }
}

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  scope: resourceGroup(rgName)
  name: '${workspaceName}-deployment'
  params: {
    name: workspaceName
    location: location
    tags: tags
    dataRetention: dataRetentionInDays
    dailyQuotaGb: dailyQuotaGb
  }
  dependsOn: [rg]
}

resource activityLogDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableActivityLogDiagnostics) {
  name: 'send-activity-log-to-log-analytics'
  properties: {
    workspaceId: workspace.outputs.resourceId
    logs: [for category in [
      'Administrative'
      'Security'
      'ServiceHealth'
      'Alert'
      'Recommendation'
      'Policy'
      'Autoscale'
      'ResourceHealth'
    ]: {
      category: category
      enabled: true
    }]
  }
}

output workspaceResourceId string = workspace.outputs.resourceId
