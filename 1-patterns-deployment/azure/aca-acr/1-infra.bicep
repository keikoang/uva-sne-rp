targetScope = 'resourceGroup'

@description('Azure region')
param location string = resourceGroup().location

@description('Globally unique ACR name, lowercase alphanumeric, 5-50 chars')
param acrName string

@description('Container App name')
param acaName string

@description('Container Apps environment name')
param containerAppsEnvName string = 'env-${acaName}'

@description('Log Analytics workspace name')
param logAnalyticsName string = 'law-${acaName}'

@description('ACA subnet NSG name')
param nsgAcaName string = 'nsg-aca'

@description('Private endpoint subnet NSG name')
param nsgPeName string = 'nsg-pe'

@description('Virtual network name')
param vnetName string = 'vnet-${acaName}'

@description('User-assigned managed identity name for the Container App')
param workloadIdentityName string = 'uami-${acaName}'

var acaSubnetName = 'snet-aca'
var privateEndpointSubnetName = 'snet-private-endpoints'
var acaSubnetCidr = '10.0.0.0/27'
var privateEndpointSubnetCidr = '10.0.1.0/24'
var acrLoginServer = '${acrName}.azurecr.io'

var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)

resource nsgAca 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
  name: nsgAcaName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-https-to-pe'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: acaSubnetCidr
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
        name: 'allow-https-from-aca'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: acaSubnetCidr
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
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: acaSubnetName
        properties: {
          addressPrefix: acaSubnetCidr
          networkSecurityGroup: {
            id: nsgAca.id
          }
          defaultOutboundAccess: false
          privateEndpointNetworkPolicies: 'Enabled'
          delegations: [
            {
              name: 'acaDelegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
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

var acaSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, acaSubnetName)
var privateEndpointSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: workloadIdentityName
  location: location
}

resource acr 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'None'
    networkRuleBypassAllowedForTasks: false
    publicNetworkAccess:'Disabled'
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, uami.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: acrPullRoleDefinitionId
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource acaEnv 'Microsoft.App/managedEnvironments@2026-01-01' = {
  name: containerAppsEnvName
  location: location
  properties: {
    publicNetworkAccess: 'Disabled'
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
      internal: true
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output acrIdOut string = acr.id
output acrLoginServerOut string = acrLoginServer
output containerAppsEnvIdOut string = acaEnv.id
output uamiIdOut string = uami.id
output uamiClientIdOut string = uami.properties.clientId
output uamiPrincipalIdOut string = uami.properties.principalId
output vnetIdOut string = vnet.id
output acaSubnetIdOut string = acaSubnetId
output privateEndpointSubnetIdOut string = privateEndpointSubnetId
