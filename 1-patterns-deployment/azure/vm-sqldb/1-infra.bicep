targetScope = 'resourceGroup'

@description('Deployment location')
param location string = resourceGroup().location

@description('Virtual machine name')
param vmName string

@description('Azure region-local computer/admin username for the Linux VM')
param adminUsername string = 'azureuser'

@description('SSH public key for the Linux VM')
param sshPublicKey string

@description('Virtual machine size')
param vmSize string = 'Standard_B2s_v2'

@description('OS disk size in GiB')
param osDiskSizeGB int = 64

@allowed([
  'Premium_LRS'
  'StandardSSD_LRS'
  'Standard_LRS'
])
@description('Managed OS disk SKU')
param osDiskStorageAccountType string = 'Premium_LRS'

@description('Virtual network name')
param vnetName string = 'vnet-${vmName}'

@description('VM subnet name')
param vmSubnetName string = 'snet-vm'

@description('Subnet reserved for future private endpoints')
param privateEndpointSubnetName string = 'snet-private-endpoints'

@description('VM subnet NSG name')
param nsgVmName string = 'nsg-vm'

@description('Private endpoint subnet NSG name')
param nsgPeName string = 'nsg-pe'

@description('NIC name')
param nicName string = 'nic-${vmName}'

@description('Azure SQL logical server name. Must be globally unique.')
param sqlServerName string

@description('Azure SQL database name')
param sqlDatabaseName string = '${sqlServerName}-db'

@description('Azure SQL database SKU name')
param sqlDbSkuName string = 'Basic'

@description('Azure SQL database SKU tier')
param sqlDbSkuTier string = 'Basic'

@description('Azure SQL auditing retention in days')
param sqlAuditRetentionDays int = 91

@description('Azure SQL short-term backup retention in days')
param sqlBackupRetentionDays int = 7

var vmSubnetCidr = '10.60.1.0/24'
var privateEndpointSubnetCidr = '10.60.2.0/24'
var vnetAddressSpace = '10.60.0.0/16'
var vmImagePublisher = 'center-for-internet-security-inc'
var vmImageOffer = 'cis-ubuntu'
var vmImageSku = 'cis-ubuntulinux2204-l1-gen2'
var vmImageVersion = 'latest'

var vmSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, vmSubnetName)
var privateEndpointSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, privateEndpointSubnetName)
var sqlServerFqdn = '${sqlServerName}.database.windows.net'
var sqlPrivateDnsZoneName = 'privatelink.database.windows.net'

resource nsgVm 'Microsoft.Network/networkSecurityGroups@2025-07-01' = {
  name: nsgVmName
  location: location
  properties: {
    securityRules: [
      {
        name: 'allow-sql-to-pe'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: vmSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetCidr
          destinationPortRange: '1433'
        }
      }
      {
        name: 'allow-https-to-internet'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: vmSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
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

resource natGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-nat-${vmName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-${vmName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natGatewayPublicIp.id
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
        name: 'allow-sql-from-vm'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: vmSubnetCidr
          sourcePortRange: '*'
          destinationAddressPrefix: privateEndpointSubnetCidr
          destinationPortRange: '1433'
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
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: vmSubnetName
        properties: {
          addressPrefix: vmSubnetCidr
          networkSecurityGroup: {
            id: nsgVm.id
          }
          natGateway: {
            id: natGateway.id
          }
          defaultOutboundAccess: false
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

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vmSubnetId
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  plan: {
    name: vmImageSku
    product: vmImageOffer
    publisher: vmImagePublisher
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: false
        vTpmEnabled: false
      }
    }
    storageProfile: {
      imageReference: {
        publisher: vmImagePublisher
        offer: vmImageOffer
        sku: vmImageSku
        version: vmImageVersion
      }
      osDisk: {
        osType: 'Linux'
        name: 'osdisk-${vmName}'
        createOption: 'FromImage'
        caching: 'ReadOnly'
        diskSizeGB: osDiskSizeGB
        managedDisk: {
          storageAccountType: osDiskStorageAccountType
        }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
          assessmentMode: 'AutomaticByPlatform'
        }
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}
resource sqlServer 'Microsoft.Sql/servers@2025-01-01' = {
  name: sqlServerName
  location: location
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    restrictOutboundNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      login: vm.name
      sid: vm.identity.principalId
      tenantId: tenant().tenantId
      principalType: 'Application'
      azureADOnlyAuthentication: true
    }
  }
}

resource sqlDb 'Microsoft.Sql/servers/databases@2025-02-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: sqlDbSkuName
    tier: sqlDbSkuTier
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

resource sqlDbBackupRetention 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2025-02-01-preview' = {
  parent: sqlDb
  name: 'default'
  properties: {
    retentionDays: sqlBackupRetentionDays
    diffBackupIntervalInHours: 24
  }
}

resource sqlServerAuditing 'Microsoft.Sql/servers/auditingSettings@2025-02-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    retentionDays: sqlAuditRetentionDays
    auditActionsAndGroups: [
      'BATCH_COMPLETED_GROUP'
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
    ]
  }
}

resource sqlServerVulnerabilityAssessment 'Microsoft.Sql/servers/sqlVulnerabilityAssessments@2022-05-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
  }
}

resource sqlAdvancedThreatProtection 'Microsoft.Sql/servers/advancedThreatProtectionSettings@2025-02-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
  }
}

output vmNameOut string = vm.name
output vmIdOut string = vm.id
output vmPrincipalIdOut string = vm.identity.principalId
output vmSubnetIdOut string = vmSubnetId
output privateEndpointSubnetIdOut string = privateEndpointSubnetId
output vnetIdOut string = vnet.id
output sqlServerIdOut string = sqlServer.id
output sqlServerNameOut string = sqlServer.name
output sqlServerFqdnOut string = sqlServerFqdn
output sqlDatabaseNameOut string = sqlDb.name
output sqlPrivateDnsZoneNameOut string = sqlPrivateDnsZoneName
