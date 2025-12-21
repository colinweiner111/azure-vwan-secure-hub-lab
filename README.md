# Azure vWAN Secure Hub Lab (two-region)

> This lab script is based on work by Daniel Mauser (see *Credits & Source* below).

This repo contains a **Bicep-based deployment** for a two-hub **Virtual WAN** lab with spokes, branch VNets, VPN Gateways, Azure Firewall (Hub), Log Analytics, and Azure Bastion. Intended for **lab/demo** use to validate secured vHub and routing intent scenarios.

> **⚠️ Important**
> These scripts create multiple VNets, gateways (which are expensive), firewalls, VMs, and public IPs. Delete the resource group when you're done.
> ```powershell
> az group delete -n <your-rg> --yes --no-wait
> ```

## Getting Started

### Clone the Repository

```powershell
git clone https://github.com/colinweiner111/azure-vwan-secure-hub-lab.git
cd azure-vwan-secure-hub-lab
```

## Deployment

Use the PowerShell deployment script:

```powershell
.\deploy-bicep.ps1 -ResourceGroupName <your-rg-name> -Location <region>
```

Example:
```powershell
.\deploy-bicep.ps1 -ResourceGroupName vwan-lab-rg -Location eastus
```

The script will:
1. Create the resource group
2. Deploy the Bicep template
3. Prompt for VM admin password if not provided

### Optional Parameters

- `-ResourceGroupName` (required): Name of the resource group
- `-Location` (optional): Azure region (default: script will prompt)

## Prerequisites

### Requirements

- Azure CLI or Azure PowerShell
- Logged in and default subscription set:
  ```powershell
  az login
  az account set --subscription "<SUBSCRIPTION_ID>"
  ```

## Quick Start

```powershell
# clone and enter
git clone https://github.com/colinweiner111/azure-vwan-secure-hub-lab.git
cd azure-vwan-secure-hub-lab

# run deployment
.\deploy-bicep.ps1 -ResourceGroupName vwan-lab-rg

# you'll be prompted for:
# - Azure region
# - VM admin password
```

## What Gets Deployed

- vWAN + two vHubs
- Three spokes per hub
- Two branch VNets with VPN Gateways (BGP)
- Azure Firewall (Hub) + Policy per hub
- Log Analytics Workspaces + diagnostic settings
- VM boot diagnostics
- Routing Intent (PrivateOnly) with next hop = Azure Firewall
- **Azure Bastion — provides browser-based RDP/SSH access to all VMs in both hubs**

## Default Configuration

- **Username**: `azureuser`
- **Password**: Prompted during deployment (set a strong password)
- **Regions**: Configured in Bicep parameters
- **VM Size**: Configured in Bicep parameters
- **Firewall SKU**: Configured in Bicep parameters

## Cleanup

When finished, delete the resource group:
```powershell
az group delete -n <your-rg> --yes --no-wait
```

## Credits & Source

This script is adapted from the excellent work in Daniel Mauser's repository:
https://github.com/dmauser/azure-virtualwan/tree/main/svh-ri-intra-region

Huge thanks to **Daniel Mauser (@dmauser)** for sharing and maintaining these scenarios and guidance.

---

© MIT Licensed. See `LICENSE`.
