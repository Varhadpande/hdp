targetScope = 'resourceGroup'

param location string = resourceGroup().location
param owner string
param environment string = 'dev'
param enableDiagnostics bool = true

param storageName string = 'prathamadlsstorage'
param kvName string = 'pratham-kv'
param adfName string = 'pratham-adf'
param lawName string = 'pratham-log'
param dbxName string = 'pratham-dbw'
param dbxConnectorName string = 'pratham-dbx-connector'

var tags = {
  project: 'healthcare-data-platform'
  environment: environment
  owner: owner
  'data-classification': 'synthetic'
}

var storageBlobDataContributorId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var dbxManagedRgName = 'databricks-rg-${dbxName}-${uniqueString(dbxName, resourceGroup().id)}'

resource lake 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: tags
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: lake
  name: 'default'
}

resource zones 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for z in ['landing', 'bronze', 'silver', 'gold']: {
  parent: blob
  name: z
}]

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: 1 }
  }
}

resource lakeDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'diag-to-law'
  scope: blob
  properties: {
    workspaceId: law.id
    logs: [
      { category: 'StorageRead', enabled: true }
      { category: 'StorageWrite', enabled: true }
      { category: 'StorageDelete', enabled: true }
    ]
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource adf 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: adfName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
}

resource adfLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(lake.id, adf.id, storageBlobDataContributorId)
  scope: lake
  properties: {
    principalId: adf.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorId)
  }
}

resource dbx 'Microsoft.Databricks/workspaces@2023-02-01' = {
  name: dbxName
  location: location
  tags: tags
  sku: { name: 'premium' }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', dbxManagedRgName)
  }
}

resource dbxConnector 'Microsoft.Databricks/accessConnectors@2024-05-01' = {
  name: dbxConnectorName
  location: location
  tags: tags
  identity: { type: 'SystemAssigned' }
}

resource dbxLakeAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(lake.id, dbxConnector.id, storageBlobDataContributorId)
  scope: lake
  properties: {
    principalId: dbxConnector.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorId)
  }
}

output storageAccountName string = lake.name
output keyVaultName string = kv.name
output dataFactoryName string = adf.name
output logAnalyticsName string = law.name
output databricksWorkspaceUrl string = dbx.properties.workspaceUrl
output accessConnectorId string = dbxConnector.id
