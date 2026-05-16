# Packer: Custom VM Image Builder

Builds Ubuntu 22.04 VM images preloaded with nginx and the React app, ready for
the VMSS in `infra/envs/{staging,prod}`.

## How it Fits

```
1. CI: npm run build  →  dist/
2. CI: az storage blob upload-batch  →  Storage Account (artifacts/latest/)
3. CI: packer build  →  reads dist/ from Storage, bakes image, publishes to SIG
4. CI: terraform apply with image_version=<new>  →  VMSS rolls
```

## Prerequisites

- `packer` 1.10+ installed (`packer --version`)
- `az` CLI logged in (`az login`) or env vars set (`ARM_*` or OIDC)
- Terraform `staging` (or `prod`) env already applied **once** — Packer
  needs the SIG and Storage Account to exist before it can publish

## Local Build (Staging)

```bash
# 1. Get values from Terraform outputs
cd ../infra/envs/staging
terraform output -json > /tmp/staging-out.json
cat /tmp/staging-out.json | jq

# 2. Fill in staging.pkrvars.hcl from those outputs
cd ../../../packer
cp staging.pkrvars.hcl.example staging.pkrvars.hcl
$EDITOR staging.pkrvars.hcl

# 3. Build a React dist/ and upload it to the artifacts container
cd ../app
npm ci
npm run build
az storage blob upload-batch \
  --account-name <storage-account-name> \
  --destination 'artifacts/latest' \
  --source dist \
  --overwrite

# 4. Generate a short-lived SAS token for Packer to download dist
EXPIRY=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%MZ')
export AZURE_STORAGE_SAS_TOKEN=$(az storage container generate-sas \
  --account-name <storage-account-name> \
  --name artifacts \
  --permissions rl \
  --expiry "$EXPIRY" \
  --auth-mode login --as-user \
  --output tsv)

# 5. Build the image
cd ../packer
packer init .
packer build -var-file=staging.pkrvars.hcl \
  -var "image_version=$(date +%Y.%m.%d-%H%M)" .
```

## Bumping the Image Version

Image versions must be unique per SIG (semver-like: `X.Y.Z`). Two patterns:

- **Class project / staging:** date-based versions (`2026.05.16-1430`) avoid
  collisions and bump automatically.
- **Production:** semantic versioning tied to git tags (`v1.2.3`). The CI
  pipeline reads the tag and strips the `v` prefix.

## After Packer Publishes

Update the env's `terraform.tfvars`:

```hcl
use_custom_image = true
image_version    = "1.0.0"  # what Packer just published
```

Then `terraform apply` — the VMSS will roll instances to the new image.

## Common Failures

**"image version already exists"**
SIG image versions are immutable. Bump `image_version` and rebuild.

**"AZURE_STORAGE_SAS_TOKEN not set" inside the build VM**
Packer didn't propagate the env var. Confirm `environment_vars` in the
`provisioner "shell"` block in `nginx-react.pkr.hcl` includes
`AZURE_STORAGE_SAS_TOKEN=${env(\"AZURE_STORAGE_SAS_TOKEN\")}`. Or pass it via
the CI step's `env:` block.

**Build hangs on apt-get update**
The Packer build VM needs internet egress. It's in a temp RG that Packer
creates with default networking — usually fine, but if your subscription has
restrictive policies (e.g. forced tunneling), you'll need to pre-create a
build VNet and reference it in the source block.

**Build succeeds but VMSS instances serve the seed page**
Terraform is still using `use_custom_image = false`. Update tfvars and
re-apply.

## Alternative: Direct dist Upload (No Storage Account Dependency)

If the Storage Account → SAS dance is too much for a class project, the
simpler path: have CI run Packer with `dist/` already on the local filesystem
and use a `file` provisioner to copy it directly to the build VM.

Replace script 03 with a Packer `file` provisioner:

```hcl
provisioner "file" {
  source      = "../app/dist/"
  destination = "/tmp/dist/"
}

provisioner "shell" {
  inline = [
    "sudo rm -rf /var/www/html/*",
    "sudo cp -r /tmp/dist/* /var/www/html/",
    "sudo chown -R www-data:www-data /var/www/html"
  ]
}
```

This loses the storage account's audit-trail value but cuts ~30 lines of
config and 3 env vars. Pick based on which story matters more to your
assignment.
