<#
.SYNOPSIS
    Azure vWAN Secure Hub Intra-Region Deployment Script (PowerShell)
.DESCRIPTION
    Converts the bash deployment script to native PowerShell for Windows.
    Deploys Virtual WAN with secure hubs, VPN gateways, Azure Firewall, and Bastion.
    NO WSL OR CLOUD SHELL REQUIRED - Runs natively in PowerShell on Windows!
#>

# =====================
# Bastion IP Connect Toggle
# Set to $true to enable Bastion IP-based connect (requires Bastion Standard).
# Set to $false to create Bastion without IP connect.
$ENABLE_BASTION_IP_CONNECT = if ($env:ENABLE_BASTION_IP_CONNECT) { 
    [System.Convert]::ToBoolean($env:ENABLE_BASTION_IP_CONNECT) 
} else { 
    $false 
}
# =====================

# Pre-Requisites
Write-Host "Validating pre-requisites..." -ForegroundColor Cyan
try {
    az extension add --name virtual-wan --only-show-errors 2>$null
    az extension add --name azure-firewall --only-show-errors 2>$null
    az extension add --name bastion --only-show-errors 2>$null
    
    # Update extensions
    az extension update --name virtual-wan --only-show-errors 2>$null
    az extension update --name azure-firewall --only-show-errors 2>$null
    az extension update --name bastion --only-show-errors 2>$null
} catch {
    Write-Host "Warning: Some extensions may already be installed" -ForegroundColor Yellow
}

# Parameters (make changes based on your requirements)
$region1 = "westus3"  # Set region1
$region2 = "westus3"  # Set region2
$rg = "vwan-securehub-v12"  # Set resource group
$vwanname = "svh-intra"  # Set vWAN name
$hub1name = "sechub1"  # Set Hub1 name
$hub2name = "sechub2"  # Set Hub2 name
$username = "azureuser"  # Set username
$password = "Msft123Msft123"  # Set password
$vmsize = "Standard_DS1_v2"  # Set VM Size
$firewallsku = "Premium"  # Azure Firewall SKU Standard or Premium

# Variables
Write-Host "Getting your public IP address..." -ForegroundColor Cyan
$mypip = (Invoke-WebRequest -Uri "https://ifconfig.io/ip" -UseBasicParsing).Content.Trim()
Write-Host "Your public IP: $mypip" -ForegroundColor Green

# Create resource group
Write-Host "Creating resource group: $rg in $region1..." -ForegroundColor Cyan
az group create -n $rg -l $region1 --output none

Write-Host "Creating vWAN and both hubs, this will take some time..." -ForegroundColor Cyan
# Create virtual wan
az network vwan create -g $rg -n $vwanname --branch-to-branch-traffic true --location $region1 --type Standard --output none
Write-Host "Creating Hub1..." -ForegroundColor Cyan
az network vhub create -g $rg --name $hub1name --address-prefix 192.168.1.0/24 --vwan $vwanname --location $region1 --sku Standard --hub-routing-preference ASPath --output none
Write-Host "Creating Hub2..." -ForegroundColor Cyan
az network vhub create -g $rg --name $hub2name --address-prefix 192.168.2.0/24 --vwan $vwanname --location $region2 --sku Standard --hub-routing-preference ASPath --output none

Write-Host "Creating branch VNET..." -ForegroundColor Cyan
# Create branch virtual network
az network vnet create --address-prefixes 10.100.0.0/16 -n branch1 -g $rg -l $region1 --subnet-name main --subnet-prefixes 10.100.0.0/24 --output none

Write-Host "Creating dedicated Bastion VNET..." -ForegroundColor Cyan
# Create dedicated Bastion VNET (separate from branch/spokes)
az network vnet create --address-prefixes 10.200.0.0/24 -n bastion-vnet -g $rg -l $region1 --subnet-name AzureBastionSubnet --subnet-prefixes 10.200.0.0/26 --output none

Write-Host "Creating spoke VNETs (2 per hub)..." -ForegroundColor Cyan
# Create spokes virtual network - Region1 (Hub1)
az network vnet create --address-prefixes 172.16.1.0/24 -n hub1-spoke1 -g $rg -l $region1 --subnet-name main --subnet-prefixes 172.16.1.0/27 --output none
az network vnet create --address-prefixes 172.16.2.0/24 -n hub1-spoke2 -g $rg -l $region1 --subnet-name main --subnet-prefixes 172.16.2.0/27 --output none
# Region2 (Hub2)
az network vnet create --address-prefixes 172.16.3.0/24 -n hub2-spoke1 -g $rg -l $region2 --subnet-name main --subnet-prefixes 172.16.3.0/27 --output none
az network vnet create --address-prefixes 172.16.4.0/24 -n hub2-spoke2 -g $rg -l $region2 --subnet-name main --subnet-prefixes 172.16.4.0/27 --output none

Write-Host "Creating VM in branch..." -ForegroundColor Cyan
az vm create -n branch1VM -g $rg --image Ubuntu2204 --public-ip-sku Standard --size $vmsize -l $region1 --subnet main --vnet-name branch1 --admin-username $username --admin-password $password --nsg '""' --os-disk-name branch1VM-osdisk --no-wait

Write-Host "Creating NSGs in both regions..." -ForegroundColor Cyan
az network nsg create --resource-group $rg --name "default-nsg-$hub1name-$region1" --location $region1 -o none
az network nsg create --resource-group $rg --name "default-nsg-$hub2name-$region2" --location $region2 -o none

az network nsg rule create -g $rg --nsg-name "default-nsg-$hub1name-$region1" -n 'default-allow-ssh' --direction Inbound --priority 100 --source-address-prefixes $mypip --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow inbound SSH" --output none
az network nsg rule create -g $rg --nsg-name "default-nsg-$hub2name-$region2" -n 'default-allow-ssh' --direction Inbound --priority 100 --source-address-prefixes $mypip --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow inbound SSH" --output none

# Add rules to allow SSH from Bastion subnet
az network nsg rule create -g $rg --nsg-name "default-nsg-$hub1name-$region1" -n 'allow-bastion-ssh' --direction Inbound --priority 110 --source-address-prefixes 10.200.0.0/26 --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow SSH from Bastion" --output none
az network nsg rule create -g $rg --nsg-name "default-nsg-$hub2name-$region2" -n 'allow-bastion-ssh' --direction Inbound --priority 110 --source-address-prefixes 10.200.0.0/26 --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 22 --access Allow --protocol Tcp --description "Allow SSH from Bastion" --output none

# Associate NSG to the VNET subnets (excluding bastion-vnet)
$region1Subnets = az network vnet list -g $rg --query "[?location=='$region1' && name!='bastion-vnet'].{id:subnets[0].id}" -o tsv
foreach ($subnetId in $region1Subnets) {
    if ($subnetId) {
        az network vnet subnet update --id $subnetId --network-security-group "default-nsg-$hub1name-$region1" -o none
    }
}

$region2Subnets = az network vnet list -g $rg --query "[?location=='$region2'].{id:subnets[0].id}" -o tsv
foreach ($subnetId in $region2Subnets) {
    if ($subnetId) {
        az network vnet subnet update --id $subnetId --network-security-group "default-nsg-$hub2name-$region2" -o none
    }
}

Write-Host "Creating VPN Gateway (this will take 20-30 minutes)..." -ForegroundColor Cyan
az network public-ip create -n branch1-vpngw-pip -g $rg --location $region1 --output none

az network vnet subnet create -g $rg --vnet-name branch1 -n GatewaySubnet --address-prefixes 10.100.100.0/26 --output none
az network vnet-gateway create -n branch1-vpngw --public-ip-addresses branch1-vpngw-pip -g $rg --vnet branch1 --asn 65010 --gateway-type Vpn -l $region1 --sku VpnGw1 --vpn-gateway-generation Generation1 --no-wait

Write-Host "Creating spoke VMs (2 per hub)..." -ForegroundColor Cyan
az vm create -n hub1-spoke1-vm -g $rg --image Ubuntu2204 --public-ip-sku Standard --size $vmsize -l $region1 --subnet main --vnet-name hub1-spoke1 --admin-username $username --admin-password $password --nsg '""' --os-disk-name hub1-spoke1-vm-osdisk --no-wait
az vm create -n hub1-spoke2-vm -g $rg --image Ubuntu2204 --public-ip-sku Standard --size $vmsize -l $region1 --subnet main --vnet-name hub1-spoke2 --admin-username $username --admin-password $password --nsg '""' --os-disk-name hub1-spoke2-vm-osdisk --no-wait
az vm create -n hub2-spoke1-vm -g $rg --image Ubuntu2204 --public-ip-sku Standard --size $vmsize -l $region2 --subnet main --vnet-name hub2-spoke1 --admin-username $username --admin-password $password --nsg '""' --os-disk-name hub2-spoke1-vm-osdisk --no-wait
az vm create -n hub2-spoke2-vm -g $rg --image Ubuntu2204 --public-ip-sku Standard --size $vmsize -l $region2 --subnet main --vnet-name hub2-spoke2 --admin-username $username --admin-password $password --nsg '""' --os-disk-name hub2-spoke2-vm-osdisk --no-wait

Write-Host "Waiting for Hub1..." -ForegroundColor Cyan
$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az network vhub show -g $rg -n $hub1name --query 'provisioningState' -o tsv
    Write-Host "$hub1name provisioningState=$prState"
    Start-Sleep -Seconds 5
}

$rtState = ''
while ($rtState -ne 'Provisioned') {
    $rtState = az network vhub show -g $rg -n $hub1name --query 'routingState' -o tsv
    Write-Host "$hub1name routingState=$rtState"
    Start-Sleep -Seconds 5
}

Write-Host "Creating Hub1 connections (2 spokes)..." -ForegroundColor Cyan
az network vhub connection create -n hub1-spoke1-conn --remote-vnet hub1-spoke1 -g $rg --vhub-name $hub1name --no-wait
az network vhub connection create -n hub1-spoke2-conn --remote-vnet hub1-spoke2 -g $rg --vhub-name $hub1name --no-wait

$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az network vhub connection show -n hub1-spoke1-conn --vhub-name $hub1name -g $rg --query 'provisioningState' -o tsv
    Write-Host "hub1-spoke1-conn provisioningState=$prState"
    if ($prState -eq 'Failed') {
        Write-Host "Connection failed, retrying..." -ForegroundColor Yellow
        az network vhub connection delete -n hub1-spoke1-conn --vhub-name $hub1name -g $rg --yes
        az network vhub connection create -n hub1-spoke1-conn --remote-vnet hub1-spoke1 -g $rg --vhub-name $hub1name --output none
        break
    }
    Start-Sleep -Seconds 5
}

$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az network vhub connection show -n hub1-spoke2-conn --vhub-name $hub1name -g $rg --query 'provisioningState' -o tsv
    Write-Host "hub1-spoke2-conn provisioningState=$prState"
    if ($prState -eq 'Failed') {
        Write-Host "Connection failed, retrying..." -ForegroundColor Yellow
        az network vhub connection delete -n hub1-spoke2-conn --vhub-name $hub1name -g $rg --yes
        az network vhub connection create -n hub1-spoke2-conn --remote-vnet hub1-spoke2 -g $rg --vhub-name $hub1name --output none
        break
    }
    Start-Sleep -Seconds 5
}

Write-Host "Creating Hub1 VPN Gateway..." -ForegroundColor Cyan
az network vpn-gateway create -n "$hub1name-vpngw" -g $rg --location $region1 --vhub $hub1name --no-wait

Write-Host "Waiting for Hub2..." -ForegroundColor Cyan
$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az network vhub show -g $rg -n $hub2name --query 'provisioningState' -o tsv
    Write-Host "$hub2name provisioningState=$prState"
    Start-Sleep -Seconds 5
}

$rtState = ''
while ($rtState -ne 'Provisioned') {
    $rtState = az network vhub show -g $rg -n $hub2name --query 'routingState' -o tsv
    Write-Host "$hub2name routingState=$rtState"
    Start-Sleep -Seconds 5
}

Write-Host "Creating Hub2 connections (2 spokes)..." -ForegroundColor Cyan
az network vhub connection create -n hub2-spoke1-conn --remote-vnet hub2-spoke1 -g $rg --vhub-name $hub2name --no-wait
az network vhub connection create -n hub2-spoke2-conn --remote-vnet hub2-spoke2 -g $rg --vhub-name $hub2name --no-wait

$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az network vhub connection show -n hub2-spoke1-conn --vhub-name $hub2name -g $rg --query 'provisioningState' -o tsv
    Write-Host "hub2-spoke1-conn provisioningState=$prState"
    if ($prState -eq 'Failed') {
        Write-Host "Connection failed, retrying..." -ForegroundColor Yellow
        az network vhub connection delete -n hub2-spoke1-conn --vhub-name $hub2name -g $rg --yes
        az network vhub connection create -n hub2-spoke1-conn --remote-vnet hub2-spoke1 -g $rg --vhub-name $hub2name --output none
        break
    }
    Start-Sleep -Seconds 5
}

$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az network vhub connection show -n hub2-spoke2-conn --vhub-name $hub2name -g $rg --query 'provisioningState' -o tsv
    Write-Host "hub2-spoke2-conn provisioningState=$prState"
    if ($prState -eq 'Failed') {
        Write-Host "Connection failed, retrying..." -ForegroundColor Yellow
        az network vhub connection delete -n hub2-spoke2-conn --vhub-name $hub2name -g $rg --yes
        az network vhub connection create -n hub2-spoke2-conn --remote-vnet hub2-spoke2 -g $rg --vhub-name $hub2name --output none
        break
    }
    Start-Sleep -Seconds 5
}

Write-Host "Creating Hub2 VPN Gateway..." -ForegroundColor Cyan
az network vpn-gateway create -n "$hub2name-vpngw" -g $rg --location $region2 --vhub $hub2name --no-wait

Write-Host "Creating Hub1 Firewall Policy..." -ForegroundColor Cyan
$fwpolicyname = "$hub1name-fwpolicy"
az network firewall policy create --name $fwpolicyname --resource-group $rg --sku $firewallsku --enable-dns-proxy true --output none --only-show-errors
az network firewall policy rule-collection-group create --name NetworkRuleCollectionGroup --priority 200 --policy-name $fwpolicyname --resource-group $rg --output none --only-show-errors

az network firewall policy rule-collection-group collection add-filter-collection `
    --resource-group $rg `
    --policy-name $fwpolicyname `
    --name GenericCollection `
    --rcg-name NetworkRuleCollectionGroup `
    --rule-type NetworkRule `
    --rule-name AnytoAny `
    --action Allow `
    --ip-protocols "Any" `
    --source-addresses "*" `
    --destination-addresses "*" `
    --destination-ports "*" `
    --collection-priority 100 `
    --output none

Write-Host "Deploying Hub1 Azure Firewall..." -ForegroundColor Cyan
$fwpolid = az network firewall policy show --resource-group $rg --name $fwpolicyname --query id --output tsv
az network firewall create -g $rg -n "$hub1name-azfw" --sku AZFW_Hub --tier $firewallsku --virtual-hub $hub1name --public-ip-count 1 --firewall-policy $fwpolid --location $region1 --output none

Write-Host "Enabling Hub1 Firewall diagnostics..." -ForegroundColor Cyan
$Workspacename = "$hub1name-$region1-Logs"
az monitor log-analytics workspace create -g $rg --workspace-name $Workspacename --location $region1 --output none

$fwId = az network firewall show --name "$hub1name-azfw" --resource-group $rg --query id -o tsv
$workspaceId = az monitor log-analytics workspace show -g $rg --workspace-name $Workspacename --query id -o tsv

az monitor diagnostic-settings create -n 'toLogAnalytics' `
    --resource $fwId `
    --workspace $workspaceId `
    --logs '[{"category":"AzureFirewallApplicationRule","Enabled":true},{"category":"AzureFirewallNetworkRule","Enabled":true},{"category":"AzureFirewallDnsProxy","Enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]' `
    --output none

Write-Host "Creating Hub2 Firewall Policy..." -ForegroundColor Cyan
$fwpolicyname = "$hub2name-fwpolicy"
az network firewall policy create --name $fwpolicyname --resource-group $rg --sku $firewallsku --enable-dns-proxy true --output none --only-show-errors
az network firewall policy rule-collection-group create --name NetworkRuleCollectionGroup --priority 200 --policy-name $fwpolicyname --resource-group $rg --output none --only-show-errors

az network firewall policy rule-collection-group collection add-filter-collection `
    --resource-group $rg `
    --policy-name $fwpolicyname `
    --name GenericCollection `
    --rcg-name NetworkRuleCollectionGroup `
    --rule-type NetworkRule `
    --rule-name AnytoAny `
    --action Allow `
    --ip-protocols "Any" `
    --source-addresses "*" `
    --destination-addresses "*" `
    --destination-ports "*" `
    --collection-priority 100 `
    --output none

Write-Host "Deploying Hub2 Azure Firewall..." -ForegroundColor Cyan
$fwpolid = az network firewall policy show --resource-group $rg --name $fwpolicyname --query id --output tsv
az network firewall create -g $rg -n "$hub2name-azfw" --sku AZFW_Hub --tier $firewallsku --virtual-hub $hub2name --public-ip-count 1 --firewall-policy $fwpolid --location $region2 --output none

Write-Host "Enabling Hub2 Firewall diagnostics..." -ForegroundColor Cyan
$Workspacename = "$hub2name-$region2-Logs"
az monitor log-analytics workspace create -g $rg --workspace-name $Workspacename --location $region2 --output none

$fwId = az network firewall show --name "$hub2name-azfw" --resource-group $rg --query id -o tsv
$workspaceId = az monitor log-analytics workspace show -g $rg --workspace-name $Workspacename --query id -o tsv

az monitor diagnostic-settings create -n 'toLogAnalytics' `
    --resource $fwId `
    --workspace $workspaceId `
    --logs '[{"category":"AzureFirewallApplicationRule","Enabled":true},{"category":"AzureFirewallNetworkRule","Enabled":true},{"category":"AzureFirewallDnsProxy","Enabled":true}]' `
    --metrics '[{"category":"AllMetrics","enabled":true}]' `
    --output none

Write-Host "Waiting for Branch1 VPN Gateway..." -ForegroundColor Cyan
$prState = az network vnet-gateway show -g $rg -n branch1-vpngw --query provisioningState -o tsv
if ($prState -eq 'Failed') {
    Write-Host "Branch1 VPN Gateway failed. Rebuilding..." -ForegroundColor Red
    az network vnet-gateway delete -n branch1-vpngw -g $rg
    az network vnet-gateway create -n branch1-vpngw --public-ip-addresses branch1-vpngw-pip -g $rg --vnet branch1 --asn 65010 --gateway-type Vpn -l $region1 --sku VpnGw1 --vpn-gateway-generation Generation1 --no-wait
} else {
    $prState = ''
    while ($prState -ne 'Succeeded') {
        $prState = az network vnet-gateway show -g $rg -n branch1-vpngw --query provisioningState -o tsv
        Write-Host "branch1-vpngw provisioningState=$prState"
        Start-Sleep -Seconds 5
    }
}

Write-Host "Waiting for vHub VPN Gateways..." -ForegroundColor Cyan
$prState = az network vpn-gateway show -g $rg -n "$hub1name-vpngw" --query provisioningState -o tsv
if ($prState -eq 'Failed') {
    Write-Host "Hub1 VPN Gateway failed. Rebuilding..." -ForegroundColor Red
    az network vpn-gateway delete -n "$hub1name-vpngw" -g $rg
    az network vpn-gateway create -n "$hub1name-vpngw" -g $rg --location $region1 --vhub $hub1name --no-wait
} else {
    $prState = ''
    while ($prState -ne 'Succeeded') {
        $prState = az network vpn-gateway show -g $rg -n "$hub1name-vpngw" --query provisioningState -o tsv
        Write-Host "$hub1name-vpngw provisioningState=$prState"
        Start-Sleep -Seconds 5
    }
}

$prState = az network vpn-gateway show -g $rg -n "$hub2name-vpngw" --query provisioningState -o tsv
if ($prState -eq 'Failed') {
    Write-Host "Hub2 VPN Gateway failed. Rebuilding..." -ForegroundColor Red
    az network vpn-gateway delete -n "$hub2name-vpngw" -g $rg
    az network vpn-gateway create -n "$hub2name-vpngw" -g $rg --location $region2 --vhub $hub2name --no-wait
} else {
    $prState = ''
    while ($prState -ne 'Succeeded') {
        $prState = az network vpn-gateway show -g $rg -n "$hub2name-vpngw" --query provisioningState -o tsv
        Write-Host "$hub2name-vpngw provisioningState=$prState"
        Start-Sleep -Seconds 5
    }
}

Write-Host "Building VPN connections..." -ForegroundColor Cyan
$bgp1 = az network vnet-gateway show -n branch1-vpngw -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv
$pip1 = az network vnet-gateway show -n branch1-vpngw -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv
$vwanh1gwbgp1 = az network vpn-gateway show -n "$hub1name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv
$vwanh1gwpip1 = az network vpn-gateway show -n "$hub1name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv
$vwanh1gwbgp2 = az network vpn-gateway show -n "$hub1name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[1].defaultBgpIpAddresses[0]' -o tsv
$vwanh1gwpip2 = az network vpn-gateway show -n "$hub1name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[1].tunnelIpAddresses[0]' -o tsv
$vwanh2gwbgp1 = az network vpn-gateway show -n "$hub2name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].defaultBgpIpAddresses[0]' -o tsv
$vwanh2gwpip1 = az network vpn-gateway show -n "$hub2name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[0].tunnelIpAddresses[0]' -o tsv
$vwanh2gwbgp2 = az network vpn-gateway show -n "$hub2name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[1].defaultBgpIpAddresses[0]' -o tsv
$vwanh2gwpip2 = az network vpn-gateway show -n "$hub2name-vpngw" -g $rg --query 'bgpSettings.bgpPeeringAddresses[1].tunnelIpAddresses[0]' -o tsv

# Create VPN site for branch1
az network vpn-site create --ip-address $pip1 -n site-branch1 -g $rg --asn 65010 --bgp-peering-address $bgp1 -l $region1 --virtual-wan $vwanname --device-model 'Azure' --device-vendor 'Microsoft' --link-speed '50' --with-link true --output none

# Connect branch1 to hub1
az network vpn-gateway connection create --gateway-name "$hub1name-vpngw" -n site-branch1-conn -g $rg --enable-bgp true --remote-vpn-site site-branch1 --internet-security --shared-key 'abc123' --output none

# Create local gateways for hub1 to branch1
az network local-gateway create -g $rg -n "lng-$hub1name-gw1" --gateway-ip-address $vwanh1gwpip1 --asn 65515 --bgp-peering-address $vwanh1gwbgp1 -l $region1 --output none
az network vpn-connection create -n "branch1-to-$hub1name-gw1" -g $rg -l $region1 --vnet-gateway1 branch1-vpngw --local-gateway2 "lng-$hub1name-gw1" --enable-bgp --shared-key 'abc123' --output none

az network local-gateway create -g $rg -n "lng-$hub1name-gw2" --gateway-ip-address $vwanh1gwpip2 --asn 65515 --bgp-peering-address $vwanh1gwbgp2 -l $region1 --output none
az network vpn-connection create -n "branch1-to-$hub1name-gw2" -g $rg -l $region1 --vnet-gateway1 branch1-vpngw --local-gateway2 "lng-$hub1name-gw2" --enable-bgp --shared-key 'abc123' --output none

# Connect branch1 to hub2
az network vpn-gateway connection create --gateway-name "$hub2name-vpngw" -n site-branch1-conn -g $rg --enable-bgp true --remote-vpn-site site-branch1 --internet-security --shared-key 'abc123' --output none

# Create local gateways for hub2 to branch1
az network local-gateway create -g $rg -n "lng-$hub2name-gw1" --gateway-ip-address $vwanh2gwpip1 --asn 65515 --bgp-peering-address $vwanh2gwbgp1 -l $region2 --output none
az network vpn-connection create -n "branch1-to-$hub2name-gw1" -g $rg -l $region1 --vnet-gateway1 branch1-vpngw --local-gateway2 "lng-$hub2name-gw1" --enable-bgp --shared-key 'abc123' --output none

az network local-gateway create -g $rg -n "lng-$hub2name-gw2" --gateway-ip-address $vwanh2gwpip2 --asn 65515 --bgp-peering-address $vwanh2gwbgp2 -l $region2 --output none
az network vpn-connection create -n "branch1-to-$hub2name-gw2" -g $rg -l $region1 --vnet-gateway1 branch1-vpngw --local-gateway2 "lng-$hub2name-gw2" --enable-bgp --shared-key 'abc123' --output none

Write-Host "Enabling Routing Intent (Private Traffic Only)..." -ForegroundColor Cyan
$nexthophub1 = az network vhub show -g $rg -n $hub1name --query azureFirewall.id -o tsv
az deployment group create --name "$hub1name-ri" `
    --resource-group $rg `
    --template-file "$PSScriptRoot\routing-intent.bicep" `
    --parameters scenarioOption=PrivateOnly hubname=$hub1name nexthop=$nexthophub1 `
    --no-wait

$nexthophub2 = az network vhub show -g $rg -n $hub2name --query azureFirewall.id -o tsv
az deployment group create --name "$hub2name-ri" `
    --resource-group $rg `
    --template-file "$PSScriptRoot\routing-intent.bicep" `
    --parameters scenarioOption=PrivateOnly hubname=$hub2name nexthop=$nexthophub2 `
    --no-wait

$subid = az account list --query "[?isDefault == ``true``].id" --all -o tsv
$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az rest --method get --uri "/subscriptions/$subid/resourceGroups/$rg/providers/Microsoft.Network/virtualHubs/$hub1name/routingIntent/${hub1name}_RoutingIntent?api-version=2022-01-01" --query 'properties.provisioningState' -o tsv
    Write-Host "$hub1name routing intent provisioningState=$prState"
    Start-Sleep -Seconds 5
}

$prState = ''
while ($prState -ne 'Succeeded') {
    $prState = az rest --method get --uri "/subscriptions/$subid/resourceGroups/$rg/providers/Microsoft.Network/virtualHubs/$hub2name/routingIntent/${hub2name}_RoutingIntent?api-version=2022-01-01" --query 'properties.provisioningState' -o tsv
    Write-Host "$hub2name routing intent provisioningState=$prState"
    Start-Sleep -Seconds 5
}

Write-Host "Core deployment completed!" -ForegroundColor Green

# BASTION DEPLOYMENT (DEDICATED VNET WITHOUT INTERNET ROUTING)
Write-Host "Starting Bastion deployment in dedicated VNET..." -ForegroundColor Cyan

try {
    Write-Host "Creating Bastion NSG with required rules..." -ForegroundColor Cyan
    az network nsg create -g $rg -n bastion-nsg -l $region1 --output none
    
    # Inbound rules
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowHttpsInbound --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes Internet --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 443 --output none
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowGatewayManagerInbound --priority 110 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes GatewayManager --source-port-ranges '*' --destination-address-prefixes '*' --destination-port-ranges 443 --output none
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowBastionHostCommunication --priority 120 --direction Inbound --access Allow --protocol '*' --source-address-prefixes VirtualNetwork --source-port-ranges '*' --destination-address-prefixes VirtualNetwork --destination-port-ranges 8080 5701 --output none
    
    # Outbound rules
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowSshRdpOutbound --priority 100 --direction Outbound --access Allow --protocol '*' --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes VirtualNetwork --destination-port-ranges 22 3389 --output none
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowAzureCloudOutbound --priority 110 --direction Outbound --access Allow --protocol Tcp --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes AzureCloud --destination-port-ranges 443 --output none
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowBastionCommunication --priority 120 --direction Outbound --access Allow --protocol '*' --source-address-prefixes VirtualNetwork --source-port-ranges '*' --destination-address-prefixes VirtualNetwork --destination-port-ranges 8080 5701 --output none
    az network nsg rule create -g $rg --nsg-name bastion-nsg -n AllowGetSessionInformation --priority 130 --direction Outbound --access Allow --protocol '*' --source-address-prefixes '*' --source-port-ranges '*' --destination-address-prefixes Internet --destination-port-ranges 80 --output none
    
    Write-Host "Attaching NSG to AzureBastionSubnet..." -ForegroundColor Cyan
    az network vnet subnet update -g $rg --vnet-name bastion-vnet -n AzureBastionSubnet --network-security-group bastion-nsg --output none
    
    Write-Host "Creating Bastion Public IP..." -ForegroundColor Cyan
    az network public-ip create -g $rg `
        -n Bastion-PIP `
        --sku Standard `
        --location $region1 `
        --output none
    
    Write-Host "Deploying Azure Bastion with IP-based connection (10-15 minutes)..." -ForegroundColor Cyan
    az network bastion create -g $rg `
        -n SharedBastion `
        --vnet-name bastion-vnet `
        --public-ip-address Bastion-PIP `
        --location $region1 `
        --sku Standard `
        --enable-ip-connect true `
        --no-wait
    
    Write-Host "Waiting for Bastion deployment to complete..." -ForegroundColor Cyan
    $bastionState = ''
    while ($bastionState -ne 'Succeeded') {
        $bastionState = az network bastion show -g $rg -n SharedBastion --query 'provisioningState' -o tsv 2>$null
        if ($bastionState -eq 'Succeeded') {
            break
        }
        if ($bastionState -eq 'Failed') {
            throw "Bastion deployment failed"
        }
        Write-Host "Bastion provisioningState=$bastionState"
        Start-Sleep -Seconds 30
    }
    
    Write-Host "Azure Bastion deployed successfully!" -ForegroundColor Green
    
    # Connect Bastion VNET to Hub1 WITHOUT internet routing intent
    Write-Host "Connecting Bastion VNET to Hub1 (without internet routing)..." -ForegroundColor Cyan
    
    # Get Bastion VNET ID
    $bastionVnetId = az network vnet show -g $rg -n bastion-vnet --query id -o tsv
    
    # Create connection without routing intent for internet (allows Bastion to work properly)
    az network vhub connection create `
        -n bastion-vnet-conn `
        --remote-vnet $bastionVnetId `
        -g $rg `
        --vhub-name $hub1name `
        --internet-security false `
        --output none
    
    Write-Host "Bastion VNET connected to Hub1 (internet routing disabled)" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR during Bastion deployment: $_" -ForegroundColor Red
    Write-Host "Core infrastructure is complete. Bastion failed." -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "ALL DEPLOYMENTS COMPLETED!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
