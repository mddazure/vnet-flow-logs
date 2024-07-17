param location string = 'westeurope'
param nicName string = 'nic'
param virtualNetworkName string = 'vnet'
param subnetName string = 'subnet'
param i int
param rgName string = 'rg'
param vmName string = 'vm'
param vmsize string = 'Standard_B1s'
param adminUsername string = 'admin'
param adminPassword string = 'adminPassword'
param imagePublisher string = 'MicrosoftWindowsServer'
param imageOffer string = 'WindowsServer'
param imageSku string = '2022-Datacenter'
param customImageId string = ''




resource nic 'Microsoft.Network/networkInterfaces@2019-09-01' =  {
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
}


resource vm 'Microsoft.Compute/virtualMachines@2018-10-01' =  {
  name: '${vmName}${i}'
  location: location
  tags:{
    group: i
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
}

resource autoshut 'Microsoft.DevTestLab/schedules@2018-09-15' =  {
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
}


resource vmName_Microsoft_Azure_NetworkWatcher 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' =  {
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
}

resource vmName_IISExtension 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' =  {
  name: 'IISExtension'
  parent: vm
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
}
