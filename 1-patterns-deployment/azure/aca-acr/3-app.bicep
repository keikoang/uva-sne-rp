targetScope = 'resourceGroup'

@description('Name of the Container App')
param acaName string

@description('Azure region')
param location string = resourceGroup().location

@description('Infra resource group name')
param infraResourceGroupName string

@description('ACR login server, for example: myregistry.azurecr.io')
param acrLoginServer string

@description('Image repository name inside ACR, for example: myapi')
param imageRepository string

@description('Image tag')
param imageTag string = '1.0'

@description('Container port your app listens on')
param targetPort int = 8080

@description('Enable ingress at all')
param enableIngress bool = true

@description('Expose ingress externally')
param externalIngress bool = false

@description('CPU in cores, for example 0.5 or 1.0')
param cpu string = '0.5'

@description('Memory, for example 1Gi or 2Gi')
param memory string = '1Gi'

@description('Minimum replicas')
param minReplicas int = 1

@description('Maximum replicas')
param maxReplicas int = 1

@description('Plain env vars or secret refs.')
param envVars array = []

@secure()
@description('Optional app secrets as key/value object.')
param secretValues object = {}

@description('Optional tags')
param tags object = {}

var uamiName = 'uami-${acaName}'

var containerAppsEnvName = 'env-${acaName}'

var image = '${acrLoginServer}/${imageRepository}:${imageTag}'

var ingressConfig = enableIngress ? {
  ingress: {
    external: externalIngress
    targetPort: targetPort
    transport: 'auto'
    allowInsecure: false
  }
} : {}

var builtInEnvVars = [
  {
    name: 'CLOUD_PROVIDER'
    value: 'azure'
  }
  {
    name: 'AZURE_REGION'
    value: location
  }
]

var secrets = [
  for s in items(secretValues): {
    name: s.key
    value: s.value
  }
]

var secretsConfig = length(items(secretValues)) > 0 ? {
  secrets: secrets
} : {}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
  scope: resourceGroup(infraResourceGroupName)
}

resource acaEnv 'Microsoft.App/managedEnvironments@2026-01-01' existing = {
  name: containerAppsEnvName
  scope: resourceGroup(infraResourceGroupName)
}

resource containerApp 'Microsoft.App/containerApps@2026-01-01' = {
  name: acaName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: acaEnv.id
    configuration: union({
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: acrLoginServer
          identity: uami.id
        }
      ]
    }, ingressConfig, secretsConfig)
    template: {
      containers: [
        {
          name: acaName
          image: image
          env: [
            for e in concat(builtInEnvVars, envVars): contains(e, 'secretRef')
              ? {
                  name: e.name
                  secretRef: e.secretRef
                }
              : {
                  name: e.name
                  value: e.value
                }
          ]
          resources: {
            cpu: json(cpu)
            memory: memory
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output containerAppId string = containerApp.id
output acaNameOut string = containerApp.name
