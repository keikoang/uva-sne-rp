param location string = resourceGroup().location
param vnetResourceId string
param pepSubnetResourceId string
param acrResourceId string 

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
}

resource acrPrivateDnsVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: acrPrivateDnsZone
  name: 'acr-vnet-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetResourceId
    }
  }
}

resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-acatoacrconnected'
  location: location
  properties: {
    subnet: {
      id: pepSubnetResourceId
    }
    privateLinkServiceConnections: [
      {
        name: 'acr-private-link'
        properties: {
          privateLinkServiceId: acrResourceId
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: acrPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'acr-private-dns'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}
