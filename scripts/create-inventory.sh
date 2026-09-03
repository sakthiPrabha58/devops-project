#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../terraform"

terraform output -json > /tmp/devshop-terraform-output.json

echo "Use terraform output above to populate ansible/inventory/hosts.ini; do not create an ansible worker entry."
echo "This script intentionally does not write SSH credentials or private keys."
