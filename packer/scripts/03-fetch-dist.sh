#!/bin/sh
# ============================================================================
# 03-fetch-dist.sh
#
# Pulls the React build (dist/) from the env's Storage Account into
# /var/www/html, then cleans up build-only tooling.
#
# Expected environment variables:
#   STORAGE_ACCOUNT  — name of the storage account
#   CONTAINER        — blob container name (typically 'artifacts')
#   BLOB_PREFIX      — path prefix inside the container (e.g. 'latest/')
#
# Authentication:
#   This script runs inside the temporary Packer build VM. That VM does NOT
#   have a managed identity with storage access by default. The simplest and
#   most reliable approach is to use the AZ CLI device authentication via the
#   build runner's credentials by passing a short-lived SAS token at build
#   time (set AZURE_STORAGE_SAS_TOKEN before invoking packer).
#
#   Alternative: enable system-assigned identity on the Packer build VM and
#   grant it Storage Blob Data Reader. Requires extra setup; left as a TODO.
# ============================================================================
set -eu

: "${STORAGE_ACCOUNT:?STORAGE_ACCOUNT is required}"
: "${CONTAINER:?CONTAINER is required}"
: "${BLOB_PREFIX:?BLOB_PREFIX is required}"

WORK_DIR="/tmp/dist-download"
mkdir -p "$WORK_DIR"

echo "[03] Fetching dist from $STORAGE_ACCOUNT/$CONTAINER/$BLOB_PREFIX"

# AZURE_STORAGE_SAS_TOKEN should be passed in via Packer env_vars at build time.
# If absent, the build fails fast with a clear message.
if [ -z "${AZURE_STORAGE_SAS_TOKEN:-}" ]; then
  echo "[03] ERROR: AZURE_STORAGE_SAS_TOKEN not set."
  echo "[03] Pass it via Packer environment_vars on the shell provisioner."
  exit 1
fi

az storage blob download-batch \
  --account-name "$STORAGE_ACCOUNT" \
  --source "$CONTAINER" \
  --destination "$WORK_DIR" \
  --pattern "${BLOB_PREFIX}*" \
  --sas-token "$AZURE_STORAGE_SAS_TOKEN"

echo "[03] Installing dist into /var/www/html"
# Strip the prefix so files land directly in /var/www/html
SRC_DIR="$WORK_DIR/${BLOB_PREFIX%/}"
if [ ! -d "$SRC_DIR" ]; then
  # If the prefix was 'latest/' the download path may differ; check both
  SRC_DIR="$WORK_DIR"
fi

# Wipe nginx's default content, then copy
rm -rf /var/www/html/*
cp -r "$SRC_DIR"/* /var/www/html/
chown -R www-data:www-data /var/www/html

echo "[03] Contents of /var/www/html:"
ls -la /var/www/html

echo "[03] Removing Azure CLI (build-only tool)"
apt-get remove -y azure-cli || true
apt-get autoremove -y

echo "[03] Cleaning apt caches"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/dist-download /tmp/nginx-spa.conf
