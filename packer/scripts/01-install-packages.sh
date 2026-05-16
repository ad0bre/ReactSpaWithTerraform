#!/bin/sh
# ============================================================================
# 01-install-packages.sh
#
# Installs nginx and the Azure CLI (needed to fetch artifacts from the
# Storage Account during build). The Azure CLI is removed at the end so it
# doesn't bloat the final image.
# ============================================================================
set -eu

echo "[01] Updating apt"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

echo "[01] Installing nginx and helpers"
apt-get install -y \
  nginx \
  curl \
  ca-certificates \
  gnupg \
  lsb-release \
  unzip

echo "[01] Installing Azure CLI (build-time only)"
# Official Microsoft install path
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

echo "[01] Versions"
nginx -v
az --version | head -1
