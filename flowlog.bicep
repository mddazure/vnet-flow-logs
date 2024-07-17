/*
Create a flow log for a virtual network
https://docs.microsoft.com/en-us/azure/templates/microsoft.network/networkwatchers/flowlogs
*/
param copies int
param flowlogSt_name string
param networkwatcher_name string
param location string
param sourceIPaddressRDP string
param rgName string
param virtualNetworkName string
param subnetName string

resource networkwatcher 'Microsoft.Network/networkWatchers@2020-11-01' = {
  name: networkwatcher_name
  location: location
  tags: {
    environment: 'Production'
  }
}

resource vnetflow 'Microsoft.Network/networkWatchers/flowLogs@2023-05-01' = [for i in range(0, copies):{
  name: 'vnetflow${i}'
  location: location
  parent: networkwatcher
  properties: {
    targetResourceId: resourceId(rgName, 'Microsoft.Network/virtualNetworks', '${virtualNetworkName}${i}')
    storageId: resourceId(rgName, 'Microsoft.Storage/storageAccounts', flowlogSt_name)
    enabled: true
    retentionPolicy: {
      enabled: true
      days: 7
    }
    format: {
      type: 'JSON'
    }
    flowAnalyticsConfiguration: {
      publicNetwork: {
        enabled: true
        intervalInSeconds: 60
        samplingRatePercentage: 100
      }
      privateNetwork: {
        enabled: true
        intervalInSeconds: 60
        samplingRatePercentage: 100
      }
    }
  }
}
]
