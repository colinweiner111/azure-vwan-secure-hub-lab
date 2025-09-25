#!/usr/bin/env bash
set -euo pipefail

# Teardown helper for the Secure Hub lab
# Usage:
#   RG=<resource-group-name> ./teardown.sh
# or edit the rg variable below.

rg="${RG:-${rg:-}}"

if [[ -z "${rg}" ]]; then
  echo "ERROR: Resource group not provided. Set RG=<name> env var or define rg in the script."
  exit 1
fi

echo "Deleting resource group: ${rg}"
az group delete -n "${rg}" --yes --no-wait
echo "Deletion submitted."