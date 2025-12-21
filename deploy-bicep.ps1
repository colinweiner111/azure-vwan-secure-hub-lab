# Azure Virtual WAN Secure Hub Lab - Bicep Deployment
# This script deploys the complete Virtual WAN infrastructure using Bicep templates

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "vwan-securehub-lab",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westus3",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminUsername = "azureuser",
    
    [Parameter(Mandatory=$false)]
    [string]$AdminPassword,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Standard', 'Premium')]
    [string]$FirewallSku = "Premium"
)

# Check if logged into Azure
Write-Host "Checking Azure login..." -ForegroundColor Cyan
$account = az account show 2>$null | ConvertFrom-Json
if (!$account) {
    Write-Host "Not logged in. Please login to Azure..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}

Write-Host "Using subscription: $($account.name) ($($account.id))" -ForegroundColor Green

# Prompt for password if not provided
if (-not $AdminPassword) {
    $SecurePassword = Read-Host -Prompt "Enter VM admin password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $AdminPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

Write-Host "`nDeployment Parameters:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroupName"
Write-Host "  Location: $Location"
Write-Host "  Admin Username: $AdminUsername"
Write-Host "  Firewall SKU: $FirewallSku"

Write-Host "`nStarting Bicep deployment (this will take approximately 60-90 minutes)..." -ForegroundColor Yellow
Write-Host "Components to deploy:" -ForegroundColor Cyan
Write-Host "  - Virtual WAN with 2 secure hubs"
Write-Host "  - 6 Virtual Networks (Branch, Bastion, 4 Spokes)"
Write-Host "  - 5 Ubuntu VMs"
Write-Host "  - Branch VPN Gateway + 2 Hub VPN Gateways"
Write-Host "  - 2 Azure Firewalls (Premium) with InternetAndPrivate routing"
Write-Host "  - Azure Bastion with IP-based connection"

$deploymentName = "vwan-securehub-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

try {
    # Deploy using Azure CLI + Bicep
    Write-Host "`nStarting deployment..." -ForegroundColor Cyan
    
    az deployment sub create `
        --name $deploymentName `
        --location $Location `
        --template-file "$PSScriptRoot\main.bicep" `
        --parameters resourceGroupName=$ResourceGroupName `
                     region1=$Location `
                     region2=$Location `
                     adminUsername=$AdminUsername `
                     adminPassword=$AdminPassword `
                     firewallSku=$FirewallSku
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✓ Deployment completed successfully!" -ForegroundColor Green
        
        Write-Host "`nNext Steps:" -ForegroundColor Yellow
        Write-Host "1. Navigate to Azure Portal > Bastion"
        Write-Host "2. Connect to VMs using IP-based connection:"
        Write-Host "   - branch1VM: 10.100.0.4"
        Write-Host "   - hub1-spoke1-vm: 172.16.1.4"
        Write-Host "   - hub1-spoke2-vm: 172.16.2.4"
        Write-Host "   - hub2-spoke1-vm: 172.16.3.4"
        Write-Host "   - hub2-spoke2-vm: 172.16.4.4"
        Write-Host "3. All spoke traffic routes through Azure Firewall (InternetAndPrivate)"
    }
    else {
        Write-Host "`n✗ Deployment failed" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "`n✗ Deployment error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
finally {
    # Clear password from memory
    $AdminPassword = $null
    [System.GC]::Collect()
}
