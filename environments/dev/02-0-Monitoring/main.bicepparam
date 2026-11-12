using '../../../02-0-Monitoring/main.bicep'

param rgName = 'rg-monitoring-dev-uksouth-01'
param location = 'uksouth'
param workspaceName = 'log-shared-dev-uksouth-001'
param dataRetentionInDays = 30
