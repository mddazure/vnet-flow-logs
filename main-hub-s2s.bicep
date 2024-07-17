@description('Username for the Virtual Machine.')
param adminUsername string = 'AzureAdmin'

@description('Password for the Virtual Machine.')
param adminPassword string = 'flowtest-2023'

@description('Location for all resources.')
param location string = resourceGroup().location

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

module vm 'vm.bicep' = [for i in range(0, copies): {
  name: 'vm${i}'
  params: {
    adminUsername: adminUsername
    adminPassword: adminPassword
    location: location
    vmsize: vmsize
    virtualNetworkName: virtualNetworkName
    subnetName: subnetName
    nicName: nicName
    vmName: vmName
    rgName: rgName
    i: i
    imagePublisher: imagePublisher
    imageOffer: imageOffer
    imageSku: imageSku
  }
  dependsOn: [
    flownsg
    flowlogst
    virtualNetwork
  ]
}]

module flowlog 'flowlog.bicep' = {
  name: 'flowlog'
  scope: resourceGroup('NetworkWatcherRG')
  params: {
    flowlogSt_name: flowlogSt_name
    networkwatcher_name: networkwatcher_name
    location: location
    sourceIPaddressRDP: sourceIPaddressRDP
    rgName: rgName
    virtualNetworkName: virtualNetworkName
    subnetName: subnetName
    copies: copies
  }
  dependsOn: [
    flownsg
    flowlogst
    virtualNetwork
  ]
}



