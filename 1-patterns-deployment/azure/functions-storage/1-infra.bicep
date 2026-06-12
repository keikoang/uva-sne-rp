targetScope = 'resourceGroup'

@description('Deployment location')
param location string = resourceGroup().location

@description('Function App name')
param functionAppName string

@description('Separate data storage account name, must be globally unique and lowercase')
param storageAccountName string

@description('Elastic Premium plan name')
param planName string = 'ep-${functionAppName}'

@description('Webapp integration subnet NSG name')
param nsgWebappName string = 'nsg-webapp'

@description('Private endpoint subnet NSG name')
param nsgPeName string = 'nsg-pe'

@description('Virtual network name')
param vnetName string = 'vnet-${functionAppName}'

@description('IP range allowed to access the SCM (Kudu) endpoint, e.g. 10.0.0.0/8')
param scmAllowedIpRange string

@description('Integration subnet for the Function App')
param integrationSubnetName string = 'snet-webapp'

@description('Subnet that will host private endpoints')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('Blob container name')
param blobContainerName string = 'input'

var functionSubnetCidr = '10.40.1.0/24'
var privateEndpointSubnetCidr = '10.40.2.0/24'
var contentShareName = take(toLower(replace('cs${functionAppName}', '-', '')), 63)

var storageBlobDataContributorRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
)

resource nsgWebapp 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
  name: nsgWebappName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-https-to-storage-tag'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: functionSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-https-to-pe'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: functionSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetCidr
          destinationPortRange: '443'
        }
      }
      {
        name: 'deny-all-outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nsgPe 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
  name: nsgPeName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-https-from-webapp'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: functionSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetCidr
          destinationPortRange: '443'
        }
      }
      {
        name: 'deny-all-inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'deny-all-outbound'
        properties: {
          priority: 4096
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2025-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/16'
      ]
    }
    subnets: [
      {
        name: integrationSubnetName
        properties: {
          addressPrefix: functionSubnetCidr
          networkSecurityGroup: {
            id: nsgWebapp.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'webapp-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          defaultOutboundAccess: false
          serviceEndpoints: [
            {
              service: 'Microsoft.Web'
            }
            {
              service: 'Microsoft.Storage'
            }
            ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetCidr
          networkSecurityGroup: {
            id: nsgPe.id
          }
          defaultOutboundAccess: false
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource plan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: planName
  location: location
  kind: 'elastic'
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    size: 'EP1'
    family: 'EP'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource hostStorage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: functionAppName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      virtualNetworkRules: [
        {
          id: '${vnet.id}/subnets/snet-webapp'
          action: 'Allow'
        }
      ]
    }
  }
}

resource hostFileService 'Microsoft.Storage/storageAccounts/fileServices@2024-01-01' = {
  parent: hostStorage
  name: 'default'
}

resource hostContentShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2024-01-01' = {
  parent: hostFileService
  name: contentShareName
}

resource dataStorage 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource dataBlobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' = {
  parent: dataStorage
  name: 'default'
}

resource dataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  parent: dataBlobService
  name: blobContainerName
  properties: {
    publicAccess: 'None'
  }
}

var hostStorageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${hostStorage.name};AccountKey=${listKeys(hostStorage.id, hostStorage.apiVersion).keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

resource functionApp 'Microsoft.Web/sites@2025-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    virtualNetworkSubnetId: '${vnet.id}/subnets/${integrationSubnetName}'
    outboundVnetRouting: {
      allTraffic: true
      contentShareTraffic: true
    }

    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      ipSecurityRestrictions: [
        {
          vnetSubnetResourceId: '${vnet.id}/subnets/${integrationSubnetName}'
          action: 'Allow'
          priority: 50
          name: 'Own Subnet'
        }
      ]
      ipSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictions: [
        {
          ipAddress: scmAllowedIpRange
          action: 'Allow'
          priority: 100
          name: 'AllowManagementNetwork'
        }
      ]
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
    }
  }
}

resource functionAppSettings 'Microsoft.Web/sites/config@2025-03-01' = {
  parent: functionApp
  name: 'appsettings'
  properties: {
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'python'
    AzureWebJobsStorage: hostStorageConnectionString
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: hostStorageConnectionString
    WEBSITE_CONTENTSHARE: contentShareName
    WEBSITE_RUN_FROM_PACKAGE: '1'
    STORAGE_ACCOUNT_NAME: dataStorage.name
    STORAGE_CONTAINER_NAME: blobContainerName
  }
}

resource functionBlobRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataStorage.id, functionApp.id, 'blob-data-contributor')
  scope: dataStorage
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleId
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppNameOut string = functionApp.name
output hostStorageAccountNameOut string = hostStorage.name
output storageAccountNameOut string = dataStorage.name
