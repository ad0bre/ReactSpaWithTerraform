# Hello SPA on Azure — Terraform + Packer + GitHub Actions

A reproducible deployment of a React single-page app on Azure, built with
Infrastructure-as-Code across two environments. Demonstrates VPC-style
networking, immutable VM images, and an approval-gated deployment pipeline.

## What This Project Is

A small React app served by nginx, running on an Azure VM Scale Set behind a
Load Balancer, with all infrastructure described in Terraform and built/deployed
through GitHub Actions. The same code deploys both **staging** and **production**
with environment-appropriate sizing, redundancy, and approval gates.

The project deliberately exercises three infrastructure pillars:

- **Networking** — a Virtual Network (Azure's "VPC") with public and private
  subnets and Network Security Groups acting as firewalls.
- **Compute** — VM Scale Set running custom Ubuntu images baked by Packer,
  fronted by an Azure Load Balancer.
- **Storage** — a Storage Account holding React build artifacts, and a Shared
  Image Gallery holding versioned VM images.

## Repository Layout

```
ReactSpaWithTerraform/
├── app/                          # React SPA (Vite)
├── terraform/
│   ├── modules/
│   │   ├── network/              # VNet, subnets, NSGs
│   │   ├── storage/              # Storage Account + Shared Image Gallery
│   │   └── compute/              # VMSS, Load Balancer, autoscale
│   └── environments/
│       ├── staging/              # wires modules with staging values
│       └── prod/                 # wires modules with prod values
├── packer/                       # builds the nginx+React VM image
│   ├── nginx-react.pkr.hcl
│   ├── files/nginx-spa.conf
│   ├── scripts/                  # 01-install, 02-configure, 03-fetch-dist
│   └── *.pkrvars.hcl.example
└── .github/workflows/
    ├── infrastructure-deploy.yml          # main pipeline
    └── SETUP.md                  # one-time GitHub configuration
```

## Architecture at a Glance

```
                       Internet
                          │
                          ▼
              ┌──────────────────────┐
              │   Azure Load         │  ◄── Public Subnet (10.x.1.0/24)
              │   Balancer           │      NSG: HTTP from anywhere
              │   Public IP          │
              └──────────┬───────────┘
                         │ HTTP 80
                         ▼
              ┌──────────────────────┐
              │   VM Scale Set       │  ◄── Private Subnet (10.x.2.0/24)
              │   (nginx + React)    │      NSG: HTTP from LB subnet only
              │   2–6 instances      │
              └──────────────────────┘
                         ▲
                         │ image pulled at boot
                         │
              ┌──────────────────────┐
              │ Shared Image Gallery │  ◄── Versioned VM images
              │ nginx-react:1.0.0    │      Published by Packer
              └──────────┬───────────┘
                         ▲
                         │ Packer reads dist/ at build
                         │
              ┌──────────────────────┐
              │   Storage Account    │  ◄── Build artifacts
              │   artifacts/dist     │      Uploaded by CI
              └──────────────────────┘
```

---

## 1. The Terraform Modules

Each module is self-contained: `main.tf`, `variables.tf`, `outputs.tf`. They
live in `terraform/modules/` and are called by the environment configurations in
`terraform/environments/`.

### `network` module

**Contains:** one Virtual Network, two subnets (public and private), two
Network Security Groups with explicit allow/deny rules, and the associations
that bind NSGs to subnets.

**Why:** the network is the foundation everything else sits on. Splitting into
public/private subnets means the Load Balancer is reachable from the internet
but the VMs themselves never are — defense in depth. NSGs are Azure's
equivalent of AWS security groups: stateful firewall rules attached to
subnets.

**Key inputs:** `vnet_cidr`, `public_subnet_cidr`, `private_subnet_cidr`,
`environment`, `resource_group_name`.

**Key outputs:** `public_subnet_id`, `private_subnet_id`, `vnet_id`. These are
the IDs that the `compute` module consumes.

**Security model:**
- Public NSG: allows HTTP/80 from `Internet` service tag, denies all else.
- Private NSG: allows HTTP/80 only from the public subnet's CIDR, allows
  Azure LB health probes (via `AzureLoadBalancer` service tag), denies all
  else.

### `storage` module

**Contains:** a Storage Account with a private `artifacts` container, plus a
Shared Image Gallery and one image definition (`nginx-react`).

**Why:** two distinct roles bundled together because they're both about
"places artifacts live." The Storage Account is where CI uploads the built
React `dist/` directory; Packer reads from here at build time. The Shared
Image Gallery (SIG) is where Packer publishes finished VM images, versioned
semver-style. The compute module references SIG images by version.

**Key inputs:** `replication_type` (LRS for staging, GRS for prod),
`environment`, `project`.

**Key outputs:** `storage_account_name`, `storage_account_id`,
`shared_image_gallery_name`, `shared_image_name`. The compute module reads the
SIG identifiers; CI reads the storage account name to know where to upload.

**Notable details:**
- Storage account names are globally unique across Azure, so a `random_string`
  suffix is appended. The `keepers` block stabilizes it per environment so it
  doesn't churn between applies.
- Blob versioning is enabled — uploads to `artifacts/` are recoverable.
- The image definition lives in SIG but image *versions* are created by Packer,
  not Terraform. Terraform sets up the container; Packer fills it.

### `compute` module

**Contains:** a public IP, an Azure Load Balancer (Standard SKU) with backend
pool, health probe, load-balancing rule, and outbound rule; a Linux VM Scale
Set with system-assigned managed identity; and an optional autoscale setting
driven by CPU.

**Why:** this is where the app actually runs. The Load Balancer terminates
internet traffic and distributes it across VMSS instances. The scale set is
in the private subnet — no public IPs on the VMs themselves. The managed
identity is granted `Storage Blob Data Reader` on the storage account
(cross-module wiring done at the env level), so VMs can read artifacts at
runtime if needed.

**Key inputs:** `private_subnet_id`, `vm_size`, `instance_count`,
`admin_ssh_public_key`, `use_custom_image`, `image_version`,
`enable_autoscale`.

**Key outputs:** `load_balancer_public_ip`, `vmss_principal_id`. The first is
the URL endpoint; the second is the managed identity ID that needs storage
access.

**The seed-image trick:** when `use_custom_image = false`, the VMSS uses
stock Ubuntu 22.04 from the Marketplace and serves a placeholder page via
cloud-init. When `true`, it uses a specific version from the SIG. This means
`terraform apply` works from a clean slate before Packer has ever run — no
chicken-and-egg.

**Autoscale:** enabled only when `enable_autoscale = true` (prod). Rules: scale
out at >75% CPU averaged over 5 min, scale in at <25%. `lifecycle.ignore_changes
= [instances]` prevents Terraform from fighting the autoscaler.

### How Modules Interact

The dependency graph is shallow but matters:

```
network ──► compute
              ▲
              │
storage ──────┘     (compute needs SIG identifiers from storage)

storage + compute identity ──► role_assignment (in env main.tf, not in any module)
```

Within an environment's `main.tf`:

1. `azurerm_resource_group` is created first.
2. `module.network` and `module.storage` run in parallel — they share only
   the resource group.
3. `module.compute` runs after both, consuming `module.network.private_subnet_id`
   and `module.storage.shared_image_gallery_name`.
4. `azurerm_role_assignment.vmss_blob_reader` runs last, wiring
   `module.compute.vmss_principal_id` to `module.storage.storage_account_id`.

This last resource is **not in any module** because it spans the boundary
between compute and storage. Putting it at the env level is the cleanest place
for cross-module wiring.

---

## 2. The Environments

Both environments live in `terraform/environments/`, each with the same four files:
`main.tf`, `variables.tf`, `outputs.tf`, `terraform.tfvars.example`. Same
modules, same wiring, different values.

### Structural Difference: State Key

Each environment has its own Terraform state file in the shared backend:

- Staging: `staging.tfstate`
- Prod: `prod.tfstate`

Both live in the same Azure Storage Account container, so credentials and
locking are consistent. Different keys mean simultaneous applies to different
envs don't block each other.

### Value Differences

| Concern | Staging | Production | Rationale |
|---|---|---|---|
| VNet CIDR | `10.10.0.0/16` | `10.20.0.0/16` | Non-overlapping — enables future peering |
| Storage replication | `LRS` (local) | `GRS` (geo-redundant) | Durability matters more in prod |
| VM size | `Standard_B1s` (1 vCPU) | `Standard_B2s` (2 vCPU) | Real load needs real capacity |
| Instance count | 1 fixed | 2 baseline, 2–6 autoscale | HA + traffic handling |
| Autoscale | Off | On (CPU-based) | Cost vs availability |
| Image version | `"latest"` | Pinned (e.g. `"1.0.0"`) | Controlled rollouts in prod |
| RG deletion | Allowed when empty | Blocked while resources exist | Prod safety guard |
| Tags | Minimal | Adds `DataClass`, `SLA`, `BackupPolicy` | Compliance/billing |

### `terraform.tfvars` Pattern

Each environment ships a `terraform.tfvars.example` with placeholder values.
Copy to `terraform.tfvars` and fill in real values:

```bash
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — at minimum, paste a real SSH public key
```

`terraform.tfvars` is in `.gitignore`. The `.example` is committed.

### Backend Configuration

The `terraform` block in each env's `main.tf` declares an Azure backend, but
the storage account name is a placeholder. Pass it at init time:

```bash
terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=<your-bootstrap-sa>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=staging.tfstate"
```

The GitHub Actions pipeline does this automatically using repo variables.

---

## 3. Packer

Packer builds the custom VM image that the VMSS uses. It's a one-shot build
tool, not infrastructure — it lives in `packer/`, not `terraform/`.

### What Packer Does

1. Spins up a temporary Ubuntu 22.04 VM in a throwaway resource group.
2. Runs three provisioner scripts inside it:
   - `01-install-packages.sh` — installs nginx and the Azure CLI.
   - `02-configure-nginx.sh` — installs an SPA-friendly nginx site config
     (with `try_files` fallback, gzip, cache headers, `/healthz` endpoint).
   - `03-fetch-dist.sh` — downloads the React `dist/` from the env's Storage
     Account using a short-lived SAS token, drops it into `/var/www/html`.
3. Deprovisions the VM (strips machine-id, SSH host keys, cloud-init state).
4. Captures the disk as a new version in the Shared Image Gallery (e.g.
   `nginx-react:1.0.0`).
5. Destroys the temporary RG.

Image versions are immutable — once `1.0.0` is published, it can never be
republished. Bumping is required for every build.

### When Packer Runs in the Deployment Flow

```
[1] Terraform creates SIG + Storage Account (first apply, seed image mode)
                    │
                    ▼
[2] CI builds React app:  npm run build  →  dist/
                    │
                    ▼
[3] CI uploads dist/ to Storage Account artifacts container
                    │
                    ▼
[4] CI generates short-lived SAS token for the artifacts container
                    │
                    ▼
[5] CI runs Packer with the SAS token in env vars
        Packer reads dist/, bakes image, publishes to SIG
                    │
                    ▼
[6] CI updates terraform.tfvars: use_custom_image = true, image_version = 1.0.X
                    │
                    ▼
[7] Terraform applies — VMSS rolls instances to new image
                    │
                    ▼
[8] Load Balancer health probes confirm new instances, traffic shifts
```

The first time you stand up an environment, you go through steps 1 → 6 → 7 in
sequence: bootstrap the infra with stock Ubuntu, then publish your first
image, then flip the variable and re-apply. Subsequent app changes only touch
steps 2–7.

### Packer Variable Files

`packer/staging.pkrvars.hcl.example` and `packer/prod.pkrvars.hcl.example`
mirror the Terraform tfvars pattern. The key differences:

- Different target resource groups (staging vs prod env RG)
- Different SIG names
- Prod replicates to multiple regions, staging only one
- Different blob prefixes (`latest/` for staging, `release/` for prod)

See `packer/README.md` for the full local-run workflow.

---

## 4. The Pipeline

A single workflow file (`.github/workflows/infrastructure-deploy.yml`) drives all
infrastructure deployment. Triggered on push to `main` when `terraform/**`
changes, plus manual `workflow_dispatch`.

### Workflow Structure

Five jobs running in sequence (except `validate`, which runs in parallel for
both envs):

```
validate (parallel matrix: staging + prod)
   │
   ▼
staging-plan      ◄── env: staging-plan (approval gate)
   │              └─ runs terraform plan -out=tfplan
   │              └─ uploads tfplan as artifact
   │              └─ renders plan to job summary
   ▼
staging-apply     ◄── env: staging-apply (approval gate)
   │              └─ downloads tfplan artifact
   │              └─ runs terraform apply tfplan
   ▼
prod-plan         ◄── env: prod-plan (approval gate)
   │              (same shape as staging-plan)
   ▼
prod-apply        ◄── env: prod-apply (approval gate)
                  (same shape as staging-apply)
```

### Plan-to-Apply Handoff

The plan job runs `terraform plan -out=tfplan -detailed-exitcode`. The exit
code matters:

- **0** — no changes; the apply job is skipped via `if:` guard.
- **1** — error; the run fails before the apply gate is reached.
- **2** — changes pending; the apply gate appears for review.

The saved `tfplan` is uploaded as a GitHub artifact along with
`.terraform.lock.hcl` (provider versions). The apply job downloads both,
re-initializes Terraform with the same backend config and provider versions,
and runs `terraform apply -auto-approve tfplan`. The `-auto-approve` is safe
here because the user already approved at the GitHub environment gate.

Plan artifacts have **24-hour retention** by design. Plans contain everything
Terraform would do (including resolved sensitive values), so they're treated
as sensitive themselves.

### Repository Variables

Set in **Settings → Secrets and variables → Actions → Variables**. None are
secrets because OIDC handles auth; these are just configuration:

| Name | Example | Purpose |
|---|---|---|
| `AZURE_CLIENT_ID` | `xxx-xxx-xxx` | Service principal app ID |
| `AZURE_TENANT_ID` | `xxx-xxx-xxx` | Azure AD tenant |
| `AZURE_SUBSCRIPTION_ID` | `xxx-xxx-xxx` | Target subscription |
| `TFSTATE_RESOURCE_GROUP` | `rg-tfstate` | From bootstrap |
| `TFSTATE_STORAGE_ACCOUNT` | `sttfstatehelloapp12345` | From bootstrap |
| `TFSTATE_CONTAINER` | `tfstate` | From bootstrap |

### Secrets

Only one is needed in practice, and even that is optional depending on how
you generate the SSH key for VMSS admin access:

| Name | When Required |
|---|---|
| (none for Azure auth) | OIDC handles it |
| `ADMIN_SSH_PUBLIC_KEY` | Optional — if you'd rather not commit the key in `terraform.tfvars`, pass via secret + `-var` flag |

The point: **OIDC means no long-lived Azure credentials in GitHub.**

### GitHub Environments

Four environments, configured in **Settings → Environments**:

| Environment | Purpose | Required reviewers |
|---|---|---|
| `staging-plan` | Approve running plan against staging | At least 1 |
| `staging-apply` | Approve applying staging plan | At least 1 |
| `prod-plan` | Approve running plan against prod | At least 1 |
| `prod-apply` | Approve applying prod plan | At least 1 (more in real teams) |

Each environment can also restrict which branches can deploy to it (set to
`main`) and add a wait timer (useful as a "cooling off" period before prod-apply).

If staging gates feel excessive for a class project, remove the required
reviewers from `staging-plan` and `staging-apply` only — the YAML doesn't
change.

### OIDC Federated Credentials

Per-environment federated credentials are required on the Azure app
registration. The subject claim must match what GitHub emits per job:

- `repo:OWNER/REPO:environment:staging-plan`
- `repo:OWNER/REPO:environment:staging-apply`
- `repo:OWNER/REPO:environment:prod-plan`
- `repo:OWNER/REPO:environment:prod-apply`
- `repo:OWNER/REPO:ref:refs/heads/main` (for the `validate` job, which has no environment)

Each is one `az ad app federated-credential create` call. The full loop is in
`.github/workflows/SETUP.md`.

### Concurrency

The workflow uses `concurrency: group: infrastructure-deploy-main, cancel-in-progress: false`.
Two merges to main can't run the pipeline in parallel against the same state,
and an in-progress apply is never cancelled (which could leave Terraform's
state locked).

---

## 5. One-Time Setup Guide

This walks through everything needed to fork the repo and stand it up in your
own Azure subscription. Should take 30–60 minutes the first time.

### Prerequisites

- An Azure subscription with `Owner` or `Contributor` role.
- A GitHub account; ability to create a repo.
- Locally installed: `az` CLI (≥2.50), `terraform` (≥1.7), `packer` (≥1.10), `node` (≥18).

### Step 1 — Clone the Repo

```bash
git clone https://github.com/OWNER/hello-spa-terraform.git
cd hello-spa-terraform
```

Or fork it via the GitHub UI and clone your fork.

### Step 2 — Log Into Azure

```bash
az login
az account set --subscription "<your-subscription-id>"
az account show  # confirm the right subscription is selected
```

Note the subscription ID and tenant ID — you'll need them in Step 5.

### Step 3 — Bootstrap the Terraform State Backend

Terraform needs a remote location for state files. This is the one piece of
Azure you create manually; Terraform manages everything else.

```bash
# Resource group for state
az group create --name rg-tfstate --location westeurope

# Storage account with a random suffix (must be globally unique)
SA_NAME="sttfstatehelloapp$RANDOM"
echo "Storage account: $SA_NAME"  # save this!

az storage account create \
  --name "$SA_NAME" \
  --resource-group rg-tfstate \
  --location westeurope \
  --sku Standard_LRS \
  --encryption-services blob \
  --min-tls-version TLS1_2

# Container for the state files
az storage container create \
  --name tfstate \
  --account-name "$SA_NAME" \
  --auth-mode login
```

**Save the storage account name** — you'll set it as a GitHub variable in
Step 6.

### Step 4 — Create the Service Principal with OIDC

```bash
# Create the app registration
APP_NAME="sp-github-helloapp"
APP_JSON=$(az ad sp create-for-rbac --name "$APP_NAME" --skip-assignment)
APP_ID=$(echo "$APP_JSON" | jq -r '.appId')
echo "App ID: $APP_ID"  # save this!

SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "Subscription: $SUB_ID"
echo "Tenant: $TENANT_ID"

# Grant Contributor on the subscription (Terraform creates resources)
az role assignment create \
  --assignee "$APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$SUB_ID"

# Grant Storage Blob Data Contributor on the state RG (Terraform writes state)
az role assignment create \
  --assignee "$APP_ID" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/rg-tfstate"
```

### Step 5 — Create Federated Credentials

You need one per GitHub environment, plus one for the `main` branch (used by
the `validate` job). Replace `OWNER/REPO` with your repo slug:

```bash
REPO="OWNER/REPO"  # e.g. "alice/hello-spa-terraform"

# One for each environment used by the pipeline
for ENV in staging-plan staging-apply prod-plan prod-apply; do
  az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters "{
      \"name\": \"github-${ENV}\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"repo:${REPO}:environment:${ENV}\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
done

# One for the validate job (runs on main, no environment)
az ad app federated-credential create \
  --id "$APP_ID" \
  --parameters "{
    \"name\": \"github-main-branch\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:${REPO}:ref:refs/heads/main\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
```

### Step 6 — Configure GitHub Repository

In the GitHub UI:

**Variables** (Settings → Secrets and variables → Actions → Variables tab):

| Name | Value |
|---|---|
| `AZURE_CLIENT_ID` | `$APP_ID` from Step 4 |
| `AZURE_TENANT_ID` | `$TENANT_ID` from Step 4 |
| `AZURE_SUBSCRIPTION_ID` | `$SUB_ID` from Step 4 |
| `TFSTATE_RESOURCE_GROUP` | `rg-tfstate` |
| `TFSTATE_STORAGE_ACCOUNT` | `$SA_NAME` from Step 3 |
| `TFSTATE_CONTAINER` | `tfstate` |

**Environments** (Settings → Environments):

Create four: `staging-plan`, `staging-apply`, `prod-plan`, `prod-apply`.

For each:
- Required reviewers: add yourself
- Deployment branches: restrict to `main`

### Step 7 — Fill in `terraform.tfvars`

```bash
# Generate an SSH key for staging
ssh-keygen -t ed25519 -C "helloapp-staging" -f ~/.ssh/helloapp_staging -N ""

# Copy the example and edit
cd terraform/environments/staging
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and replace the placeholder `admin_ssh_public_key`
with the contents of `~/.ssh/helloapp_staging.pub`. Repeat for prod with a
separate key (`~/.ssh/helloapp_prod`).

**Do not commit `terraform.tfvars` — it's gitignored on purpose.**

For the pipeline to run, you have two options:
1. Commit the keys (acceptable for a class project — they're public keys, the
   private keys stay on your machine).
2. Add `ADMIN_SSH_PUBLIC_KEY` as a repo secret and modify the workflow to
   pass `-var "admin_ssh_public_key=$ADMIN_SSH_PUBLIC_KEY"`.

For now, option 1 is fine. Rename `terraform.tfvars` to `terraform.auto.tfvars`
in both env folders (this version *is* picked up by Terraform automatically
and we'll commit it intentionally for the pipeline's benefit).

### Step 8 — First Apply (Locally)

Before letting CI drive, verify everything works locally:

```bash
cd terraform/environments/staging

terraform init \
  -backend-config="resource_group_name=rg-tfstate" \
  -backend-config="storage_account_name=$SA_NAME" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=staging.tfstate"

terraform plan
terraform apply
```

This deploys staging with the **seed Ubuntu image** (no Packer involvement).
You should see a Load Balancer public IP in the output. Browse to it — you'll
see the placeholder "seed instance" page from `cloud-init.yaml`.

### Step 9 — Build Your First Image with Packer

```bash
# Build the React app
cd ../../../app
npm ci
npm run build

# Upload dist/ to the staging storage account
SA_STAGING=$(cd ../terraform/environments/staging && terraform output -raw storage_account_name)
az storage blob upload-batch \
  --account-name "$SA_STAGING" \
  --destination 'artifacts/latest' \
  --source dist \
  --overwrite \
  --auth-mode login

# Generate a SAS token for Packer to use
EXPIRY=$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%MZ')
export AZURE_STORAGE_SAS_TOKEN=$(az storage container generate-sas \
  --account-name "$SA_STAGING" \
  --name artifacts \
  --permissions rl \
  --expiry "$EXPIRY" \
  --auth-mode login --as-user \
  --output tsv)

# Configure Packer vars
cd ../packer
cp staging.pkrvars.hcl.example staging.pkrvars.hcl
# Edit staging.pkrvars.hcl with the values from `terraform output`:
#   - target_resource_group_name
#   - shared_image_gallery_name
#   - storage_account_name
#   - subscription_id

# Build
packer init .
packer build \
  -var-file=staging.pkrvars.hcl \
  -var "image_version=1.0.0" .
```

Packer will spin up a temp VM, install nginx, fetch your dist/, snapshot,
and publish `nginx-react:1.0.0` to the staging SIG. Takes ~5–10 minutes.

### Step 10 — Re-apply Terraform with the Custom Image

Edit `terraform/environments/staging/terraform.auto.tfvars`:

```hcl
use_custom_image = true
image_version    = "1.0.0"
```

Then:

```bash
cd ../terraform/environments/staging
terraform apply
```

The VMSS rolls instances to the new image. Browse the LB public IP again — you
should now see your React app.

### Step 11 — Drive It from CI

Commit and push:

```bash
git add terraform/environments/staging/terraform.auto.tfvars terraform/environments/prod/terraform.auto.tfvars
git commit -m "Configure environments for first deploy"
git push origin main
```

The `infrastructure-deploy.yml` workflow runs:

1. `validate` runs automatically (~1 min).
2. Go to Actions → the running workflow → click **Review deployments** to
   approve `staging-plan`.
3. Plan runs. Read it in the job summary.
4. Approve `staging-apply`. Apply runs.
5. Approve `prod-plan`. Plan runs.
6. Approve `prod-apply`. Apply runs.

You now have both environments deployed via CI with approval gates at every
sensitive step.

### Step 12 — Repeat for Production

To build a prod image, the steps mirror Step 9 but against the prod
environment. The prod storage account and SIG are in `rg-helloapp-prod`. The
prod tfvars file pins to a specific version rather than `"latest"`.

---

## Common Operations

### Deploying a new version of the React app

1. Make changes in `app/`.
2. Locally or in a separate CI workflow: `npm run build`, upload to storage,
   run Packer with a bumped version (e.g. `1.0.1`).
3. Update `image_version` in the env's tfvars.
4. Push to main; the pipeline rolls the VMSS.

### Tearing down an environment

```bash
cd terraform/environments/staging
terraform destroy
```

The bootstrap state RG (`rg-tfstate`) is **not** managed by Terraform — destroy
it manually with `az group delete --name rg-tfstate --yes`.

### Debugging a failed apply

- **State locked**: someone else's apply is in flight, or a previous run
  crashed. Wait 15 minutes for the blob lease to expire, then retry.
- **Plan expired (>24h)**: plan artifacts are kept 24 hours by design. Re-run
  the workflow from scratch.
- **OIDC auth fails**: federated credential subject mismatch. Check the
  workflow run logs for the exact subject claim emitted; recreate the
  credential with that subject.

### Rotating credentials

OIDC means there's nothing to rotate on a schedule. To revoke access entirely:
delete the service principal in Azure AD. To rotate subjects (e.g. moving the
repo): delete and recreate the federated credentials with the new repo slug.

---

## What This Project Doesn't Do (and Why)

Honest limitations worth knowing:

- **No TLS.** Class-project simplification. Real production would add a
  certificate to the Load Balancer or front everything with Azure Front Door /
  Application Gateway.
- **No custom domain.** The app is reached via the LB's raw public IP.
- **No CDN.** A real SPA deployment would put a CDN in front for caching and
  global edge delivery. Storage Account static-website hosting would be simpler
  and probably correct for a real "hello world" app — but doesn't exercise
  VPC/compute/storage as a learning project.
- **No monitoring/alerting.** Application Insights, Log Analytics, and alerts
  are out of scope.
- **No app-side CI.** The pipeline only handles infra. A real project would
  add `app-ci.yml` (test/lint/build on PR) and `image-build.yml` (Packer on
  merge).
- **State backend isn't itself in Terraform.** Bootstrap is manual on purpose —
  it's a chicken-and-egg, and the standard pattern is to accept the bootstrap
  step rather than write recursive IaC.
