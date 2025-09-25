# Azure vWAN Secure Hub Lab (two-region)

> This lab script is based on work by Daniel Mauser (see *Credits & Source* below).

This repo contains two Azure CLI/bash scripts that deploy a two‑hub **Virtual WAN** lab with spokes, branch VNets, VPN Gateways, Azure Firewall (Hub), Log Analytics, and optional Bastion. They are intended for **lab/demo** use to validate secured vHub and routing intent scenarios.

> **⚠️ Cost & Quota Notice**  
> These scripts create multiple VNets, gateways (which are expensive), firewalls, VMs, and public IPs. Delete the resource group when you're done.
> ```bash
> az group delete -n <your-rg> --yes --no-wait
> ```

## Script

- `svhri-intra-deploy-cxdemo.sh` — single script with toggle for Bastion IP Connect.

## Prerequisites

- Azure CLI >= 2.60
- Logged in and default subscription set:
  ```bash
  az login
  az account set --subscription "<SUBSCRIPTION_ID>"
  ```
- CLI extensions are handled by the scripts (`virtual-wan`, `azure-firewall`, `bastion`).

## Quick start
```bash
# clone and enter
git clone <your-repo-url>.git
cd azure-vwan-secure-hub-lab

# make scripts executable
chmod +x svhri-intra-deploy-cxdemo.sh

# (optional) edit parameters at the top of the script(s)
# IMPORTANT: change the default admin password before running

# run one of them
./svhri-intra-deploy-cxdemo.sh
```

### Parameters

- `ENABLE_BASTION_IP_CONNECT` (env var; default `false`) — set to `true` to enable Bastion IP connect (adds `--sku Standard --enable-ip-connect`).
At the top of the scripts you can change:
- `region1`, `region2`
- `rg` — `vwanname`, `hub1name`, `hub2name`
- `username`, `password` (**set a strong password** or consider using `--generate-ssh-keys` with Linux VMs)
- `vmsize`, `firewallsku`

## Recommended improvements (optional)

- Replace inline password with SSH keys or `az vm create ... --generate-ssh-keys`.
- Parameterize via environment file:
  ```bash
  cp env.sample .env
  # edit .env, then
  set -a; source .env; set +a
  ./svhri-intra-deploy-cxdemo-1.sh
  ```
- Add teardown helper:
  ```bash
  az group delete -n $rg --yes --no-wait
  ```

## How to publish this repo to GitHub (command line)
### Option A: Using `gh` (GitHub CLI)
```bash
# install gh if needed: https://cli.github.com/
cd azure-vwan-secure-hub-lab
git init
git add .
git commit -m "Initial commit: Azure vWAN Secure Hub lab scripts"
gh repo create colinweiner111/azure-vwan-secure-hub-lab --public --source=. --remote=origin --push
```

### Option B: Using plain git + GitHub web
```bash
cd azure-vwan-secure-hub-lab
git init
git add .
git commit -m "Initial commit: Azure vWAN Secure Hub lab scripts"
git branch -M main
git remote add origin https://github.com/<your-user>/azure-vwan-secure-hub-lab.git
git push -u origin main
```

## Cleanup
When finished, delete the resource group created by the script(s):
```bash
az group delete -n <rg-from-script> --yes --no-wait
```


## Credits & Source

This script is adapted from the excellent work in Daniel Mauser’s repository:  
<https://github.com/dmauser/azure-virtualwan/tree/main/svh-ri-intra-region>

Huge thanks to **Daniel Mauser (@dmauser)** for sharing and maintaining these scenarios and guidance.

---
© MIT Licensed. See `LICENSE`.
