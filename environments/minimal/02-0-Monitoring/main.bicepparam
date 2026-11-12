using '../../../02-0-Monitoring/main.bicep'

param rgName = 'rg-monitoring-dev-swedencentral-01'
param location = 'swedencentral'
param workspaceName = 'log-shared-dev-swedencentral-001'
param dataRetentionInDays = 30
// Caps ingestion cost for the minimal environment; data above the cap is dropped until the daily reset.
param dailyQuotaGb = '10'
param tags = {
  environment: 'minimal'
  workload: 'aks-landing-zone'
}
