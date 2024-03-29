@description('Username for the Virtual Machine.')
param adminUsername string = 'AzureAdmin'

@description('Password for the Virtual Machine.')
param adminPassword string = 'flowtest-2023'

@description('Location for all resources.')
param location string = 'eastus'

@description('Number of VNETs and VMs to deploy')
@minValue(1)
@maxValue(254)
param copies int = 10

param vmsize string = 'Standard_D2s_v5'

@description('Prefix Name of VNETs')
param virtualNetworkName string = 'flow-vnet-'
param virtualNetworkTagGr1 string = 'Production'
param virtualNetworkTagGr2 string = 'Development'

@description('Name of the resource group')
param rgName string = resourceGroup().name

@description('remote desktop source address')
param sourceIPaddressRDP string = '217.121.228.158'

@description('Name of the subnet to create in the virtual network')
param subnetName string = 'vmSubnet'
param gwsubnetName string = 'GatewaySubnet'
param bastionsubnetName string = 'AzureBastionSubnet'

@description('Prefix name of the nic of the vm')
param nicName string = 'VMNic-'

@description('Prefix name of the nic of the vm')
param vmName string = 'VM-'

@description('Flow log storage account name')
param flowlogSt_name string = 'flowlog${resourceGroup().name}'

@description('Flow log name')
param flowlog_name string = 'flowlog'

@description('Network watcher name')
param networkwatcher_name string = 'NetworkWatcher_${location}'

//var customImageId = '/subscriptions/0245be41-c89b-4b46-a3cc-a705c90cd1e8/resourceGroups/image-gallery-rg/providers/Microsoft.Compute/galleries/mddimagegallery/images/windows2019-networktools/versions/2.0.0'

var imagePublisher = 'MicrosoftWindowsServer'
var imageOffer = 'WindowsServer'
var imageSku = '2022-Datacenter'


resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-09-01' = [for i in range(0, copies): {
  name: '${virtualNetworkName}${i}'
  location: location
  tags:{
    group: (i<copies/2 ? virtualNetworkTagGr1 : virtualNetworkTagGr2)
  }
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.${i}.0/24'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.0.${i}.0/25'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          networkSecurityGroup: {
            id: flownsg.id
          }
        }
      }
      {
        name: gwsubnetName
        properties: {
          addressPrefix: '10.0.${i}.128/27'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: bastionsubnetName
        properties: {
          addressPrefix: '10.0.${i}.192/26'
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
    virtualNetworkPeerings: [
      {
        name: 'lowhigh'
        properties: {
          allowVirtualNetworkAccess: true
          allowForwardedTraffic: true
          allowGatewayTransit: false
          useRemoteGateways: false
          remoteVirtualNetwork: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks', '${virtualNetworkName}${(i<copies/2 ? (copies/2) : 0)}')
          }
        }
      }
      {
        name: 'highlow'
        properties: {
          allowVirtualNetworkAccess: true
          allowForwardedTraffic: true
          allowGatewayTransit: false
          useRemoteGateways: false
          remoteVirtualNetwork: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks', '${virtualNetworkName}${(i<copies/2 ? 0 : (copies/2))}')
          }
        }
      }
    ]
  }
}]



resource flownsg 'Microsoft.Network/networkSecurityGroups@2022-09-01' = {
  name: 'anvm-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'denyRFC1918-out'
        properties: {
          priority: 150
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          destinationAddressPrefixes: [
            '10.0.0.0/8'
            '172.16.0.0/12'
            '192.168.0.0/24'
          ]
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          sourcePortRange:'*'
        }
      }

    ]
  }
}
resource flowlogst 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: flowlogSt_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}


resource hubbastion 'Microsoft.Network/bastionHosts@2022-09-01' =  {
  name: 'hubbastion-0'
  dependsOn:[
    bastionpip
    virtualNetwork
  ]
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    enableShareableLink: true
    enableIpConnect: true
    ipConfigurations: [
      {
        name: 'ipConf'
        properties: {
          publicIPAddress: {
            id: bastionpip.id
          }
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', 'flow-vnet-0', bastionsubnetName)
          }
        }
      }
    ]
  }
}


resource bastionpip 'Microsoft.Network/publicIPAddresses@2022-09-01' =  {
  name: 'hubbastionpip'
  location: location
  sku: {
    name: 'Standard'
  }
  zones:[
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource hubgw 'Microsoft.Network/virtualNetworkGateways@2022-09-01' = [for i in [0,copies/2]:{
  name: 'hubgw-${i}'
  location: location
  tags:{
    group: (i<copies/2 ? virtualNetworkTagGr1 : virtualNetworkTagGr2)
  }
  dependsOn: [
    hubgwpubip
    virtualNetwork
  ]
  properties: {
    sku: {
      name: 'VpnGw1AZ'
      tier: 'VpnGw1AZ'
    }
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    enablePrivateIpAddress: true
    activeActive: false
    enableBgp: true
    bgpSettings: {
      asn: 64000+i
    }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: {
            id: resourceId(rgName, 'Microsoft.Network/publicIPAddresses', 'hubgwpip-${i}')
          }
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', 'flow-vnet-${i}', gwsubnetName)
          }
        }
      }
    ]
  }
}]

resource connlowhigh 'Microsoft.Network/connections@2022-09-01' = {
  name: 'conn-low-high'
  location: location
  properties: {
    connectionType:  'Vnet2Vnet'
    enableBgp: true
    sharedKey: 'tunnelKey'
    virtualNetworkGateway1: {
      id: hubgw[0].id
      properties: {
      }
    }
    virtualNetworkGateway2:{
      properties:{
      }
      id: hubgw[1].id
    }
  }
}

resource connhighlow 'Microsoft.Network/connections@2022-09-01' = {
  name: 'conn-high-low'
  location: location
  properties: {
    connectionType:  'Vnet2Vnet'
    enableBgp: true
    sharedKey: 'tunnelKey'
    virtualNetworkGateway1: {
      id: hubgw[1].id
      properties: {
      }
    }
    virtualNetworkGateway2:{
      properties:{
      }
      id: hubgw[0].id
    }
  }
}

resource hubgwpubip 'Microsoft.Network/publicIPAddresses@2022-09-01' = [for i in [0,copies/2]:{
  name: 'hubgwpip-${i}'
  location: location
  sku: {
    tier: 'Regional'
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
}]

resource nic 'Microsoft.Network/networkInterfaces@2019-09-01' = [for i in [0,1,2,copies/2,(copies/2)+1,(copies/2+2)]: {
  name: '${nicName}${i}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId(rgName, 'Microsoft.Network/virtualNetworks/subnets', '${virtualNetworkName}${i}', subnetName)
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
  dependsOn: [
    virtualNetwork
  ]
}]


resource vm 'Microsoft.Compute/virtualMachines@2018-10-01' = [for i in [0,1,2,copies/2,(copies/2)+1,(copies/2+2)]: {
  name: '${vmName}${i}'
  location: location
  tags:{
    group: (i<copies/2 ? virtualNetworkTagGr1 : virtualNetworkTagGr2)
  }
  properties: {
    hardwareProfile: {
      vmSize: vmsize
    }
    osProfile: {
      computerName: '${vmName}${i}'
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        //id: customImageId
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: 'latest'
      }
      osDisk: {
        name: 'osDisk-${vmName}${i}'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: resourceId('Microsoft.Network/networkInterfaces', '${nicName}${i}')
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: false
      }
    }
  }
  dependsOn: [
    nic
  ]
}]

resource autoshut 'Microsoft.DevTestLab/schedules@2018-09-15' = [for i in [0,1,2,copies/2,(copies/2)+1,(copies/2+2)]: {
  name: 'shutdown-computevm-${vmName}${i}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: '17:00'
    }
    timeZoneId: 'W. Europe Standard Time'
    targetResourceId: resourceId('Microsoft.Compute/virtualMachines','${vmName}${i}')
  }
  dependsOn: [
    vm
  ]
}]


resource vmName_Microsoft_Azure_NetworkWatcher 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = [for i in [0,1,2,copies/2,(copies/2+1),(copies/2+2)]: {
  name: '${vmName}${i}/Microsoft.Azure.NetworkWatcher'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.NetworkWatcher'
    type: 'NetworkWatcherAgentWindows'
    typeHandlerVersion: '1.4'
    autoUpgradeMinorVersion: true
  }
  dependsOn: [
    vm
  ]
}]

resource vmName_IISExtension 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = [for i in [0,1,2,copies/2,(copies/2+1),(copies/2+2)]: {
  name: '${vmName}${i}/IISExtension'
  location: location
  properties: {
    autoUpgradeMinorVersion: true
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.9'
    settings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted Add-WindowsFeature Web-Server; powershell -ExecutionPolicy Unrestricted Add-Content -Path "C:\\inetpub\\wwwroot\\Default.htm" -Value $($env:computername)'
    }
    protectedSettings: {
    }
  }
  dependsOn: [
    vm
   ]
}]

resource networkwatcher 'Microsoft.Network/networkWatchers@2022-09-01' existing = {
  name: networkwatcher_name
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


