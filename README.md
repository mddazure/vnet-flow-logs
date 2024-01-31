# VNET Flow Logs Demo Lab

This is a lab to demonstrate and experiment with [VNET Flow Logs](https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview)

:point_right: VNet flow logs is currently in PREVIEW. This preview version is provided without a service level agreement, and is not recommended for production workloads.

## Components
The lab consists of following elements:
- A set of VNETs:
  - Quantity is controlled by the `copies` parameter, (default: 20).
- Network Security Group:
  - Applied to the subnet `vmSubnet` in each VNET.
  - Contains an outbound rule denying traffic to private (RFC1918) ranges.
- Windows Server VMs:
  - In VNETs 0, 1, 2, and `copies`/2 (default: 10), `copies`/2+1 (11), `copies`/2+2 (12).
  - Each VM runs a basic webpage that returns the VM name.
- Bastion Hosts:
  - In VNETs 0 and `copies/2` (10).

## Lab Deployment

Log in to Azure Cloud Shell at https://shell.azure.com/ and select Bash.

Ensure Azure CLI and extensions are up to date:
  
```
az upgrade --yes
```
  
If necessary select your target subscription:
  
```
az account set --subscription <Name or ID of subscription>
```
  
Clone the  GitHub repository:

```
git clone https://github.com/mddazure/vnet-flow-logs
```

Change directory:

```
cd ./vnet-flow-logs
```

Create a new resource group:

```
az group create --name {rgname} --location eastus
```

Deploy the bicep template:

```
az deployment group create -g {rgname} --template-file ./main-hub-s2s.bicep
```