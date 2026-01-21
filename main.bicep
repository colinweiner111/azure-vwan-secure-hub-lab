targetScope = 'subscription'

@description('Primary region for deployment')
param region1 string = 'westus3'

@description('Secondary region for deployment (same as primary for intra-region)')
param region2 string = 'westus3'

@description('Resource group name')
param resourceGroupName string = 'vwan-securehub-lab'

@description('Virtual WAN name')
param vwanName string = 'vwan-demo'

@description('Hub 1 name')
param hub1Name string = 'hub1'

@description('Hub 2 name')
param hub2Name string = 'hub2'

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@description('Admin password for VMs')
@secure()
param adminPassword string

@description('VM size')
param vmSize string = 'Standard_DS1_v2'

@description('Azure Firewall SKU')
@allowed(['Standard', 'Premium'])
param firewallSku string = 'Premium'

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: region1
}

// Network Infrastructure
module network 'modules/network.bicep' = {
  scope: rg
  name: 'network-deployment'
  params: {
    location: region1
    vwanName: vwanName
    hub1Name: hub1Name
    hub2Name: hub2Name
  }
}

// Virtual Machines
module vms 'modules/vms.bicep' = {
  scope: rg
  name: 'vms-deployment'
  params: {
    location: region1
    adminUsername: adminUsername
    adminPassword: adminPassword
    vmSize: vmSize
    hub1Name: hub1Name
    hub2Name: hub2Name
  }
  dependsOn: [
    network
  ]
}

// VPN Infrastructure
module vpn 'modules/vpn.bicep' = {
  scope: rg
  name: 'vpn-deployment'
  params: {
    location: region1
    hub1Name: hub1Name
    hub2Name: hub2Name
    vwanName: vwanName
    branchVnetId: network.outputs.branchVnetId
    hub1Id: network.outputs.hub1Id
    hub2Id: network.outputs.hub2Id
  }
  dependsOn: [
    network
  ]
}

// Azure Firewall and Routing Intent
module firewall 'modules/firewall.bicep' = {
  scope: rg
  name: 'firewall-deployment'
  params: {
    location: region1
    hub1Name: hub1Name
    hub2Name: hub2Name
    firewallSku: firewallSku
  }
  dependsOn: [
    network
    vpn
  ]
}

// Azure Bastion
module bastion 'modules/bastion.bicep' = {
  scope: rg
  name: 'bastion-deployment'
  params: {
    location: region1
    hub1Name: hub1Name
  }
  dependsOn: [
    network
    firewall
  ]
}

output vwanId string = network.outputs.vwanId
output hub1Id string = network.outputs.hub1Id
output hub2Id string = network.outputs.hub2Id
output bastionName string = bastion.outputs.bastionName

