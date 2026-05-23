# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is an Internal Developer Platform (IDP) built on AWS. It consists of three main components:

1. **Backstage App** (`backstage-app/backstage/`) — A Backstage developer portal (TypeScript/React frontend + Node.js backend) that serves as the IDP UI.
2. **Software Templates** (`backstage-software-templates/`) — Backstage scaffolder templates that provision new services (currently Python/Flask; Go template directory is empty).
3. **Infrastructure** (`terraform/`) — Terraform code that provisions the AWS EKS cluster and VPC where everything runs.

## Backstage App Commands

All commands run from `backstage-app/backstage/` using Yarn (v4.4.1, Berry). Node 22 or 24 required.

```bash
# Start both frontend and backend in dev mode
yarn start

# Build backend only
yarn build:backend

# Build everything
yarn build:all

# Type check
yarn tsc

# Lint (only changed files since origin/master)
yarn lint

# Lint all files
yarn lint:all

# Run tests
yarn test

# Run tests with coverage
yarn test:all

# Run a single test file
yarn test packages/app/src/App.test.tsx

# E2E tests (Playwright)
yarn test:e2e

# Format check
yarn prettier:check

# Scaffold a new plugin or package
yarn new
```

## Architecture

### Backstage App

The app uses Backstage's **New Frontend System** (`@backstage/frontend-defaults`, `createApp`) and **New Backend System** (`@backstage/backend-defaults`, `createBackend`).

- **Frontend** (`packages/app/src/App.tsx`): Mounts `catalogPlugin` and a custom `navModule`. GitHub OAuth sign-in is wired via `githubAuthApiRef`. The catalog index page is set as the root (`/`). Custom nav items are rendered via `packages/app/src/modules/nav/Sidebar.tsx` (standard nav items are disabled in `app-config.yaml`).
- **Backend** (`packages/backend/src/index.ts`): Registers plugins for catalog, scaffolder (with GitHub module), techdocs, auth (GitHub + guest providers), permissions (allow-all policy), search (PostgreSQL engine), notifications, signals, and MCP actions.
- **Config layering**: `app-config.yaml` (base/dev, uses SQLite in-memory) → `app-config.local.yaml` (local overrides: GitHub auth, catalog locations, PostgreSQL) → `app-config.production.yaml` (production: PostgreSQL, GitHub OAuth, catalog file targets at `/app/entities/`).

### Software Templates

Templates live in `backstage-software-templates/<template-type>/`. Each template has:
- `template.yaml` — Backstage scaffolder spec (parameters, steps, outputs). Uses `fetch:template`, `publish:github`, and `catalog:register` actions.
- `template/` — Cookiecutter-style files with `${{values.*}}` placeholders. The two key placeholder variables are `app_name` and `app_env`.

**Python template generates:**
- Flask app (`src/app.py`) with `/api/v1/info` and `/api/v1/healthz` endpoints
- Helm chart under `charts/${{values.app_name}}/`
- ArgoCD values (`charts/argocd/values-argo.yaml`)
- Raw K8s manifests (`k8s/`)
- Terraform for ECR repository (`terraform/main.tf`)
- Two GitHub Actions workflows:
  - `*-infra.yaml`: Triggered on `terraform/**` changes → runs `terraform apply` to provision ECR
  - `*-cicd.yaml`: Triggered on `src/**` changes (or after infra workflow) → builds Docker image, pushes to ECR, updates `values.yaml` image tag, then deploys via ArgoCD CLI on a self-hosted runner

### Infrastructure (Terraform)

`terraform/main.tf` provisions:
- VPC (`terraform-aws-modules/vpc`) in `eu-west-2` with 3 AZs, public/private subnets, single NAT gateway
- EKS cluster (`terraform-aws-modules/eks` ~21.0) named `eks-cluster`, Kubernetes 1.33, using EKS Auto Mode (`compute_config.enabled = true`, `general-purpose` node pool)

### Kubernetes Deployment

Backstage itself is deployed to the EKS cluster via manifests in `backstage-app/backstage/charts/`:
- `backstage.yaml`: Deployment + Service + Ingress (nginx ingress, ALB annotations, domain `backstage.olaolat.com`)
- `values-postgres.yaml`: PostgreSQL Helm values
- ECR image: `public.ecr.aws/r1j8z0t4/idp/backstage`

### Catalog Entities

Users and groups are defined in `backstage-app/backstage/catalog/entities/`. In production these are mounted at `/app/entities/` in the container.

## Required Environment Variables

For local development, set these before running `yarn start`:

| Variable | Purpose |
|---|---|
| `GITHUB_TOKEN` | GitHub PAT for catalog/template integration |
| `AUTH_GITHUB_CLIENT_ID` | GitHub OAuth App client ID |
| `AUTH_GITHUB_CLIENT_SECRET` | GitHub OAuth App secret |

For production (PostgreSQL):

| Variable | Purpose |
|---|---|
| `POSTGRES_HOST` | PostgreSQL host |
| `POSTGRES_USER` | PostgreSQL user |
| `POSTGRES_PASSWORD` | PostgreSQL password |

## Key Conventions

- Template placeholder syntax is `${{values.variable_name}}` (double braces, not Jinja-style `{{ }}`). This distinguishes Backstage template variables from GitHub Actions expressions (`${{ }}`).
- The CI/CD pipeline for generated apps uses a **self-hosted GitHub Actions runner** (must be registered on the EKS cluster) for the CD job that runs `argocd` CLI commands.
- ArgoCD is expected at `argocd-server.argocd` (in-cluster service URL); the ArgoCD password comes from `secrets.ARGOCD_PASSWORD`.
- Generated apps deploy to a Kubernetes namespace matching `app_env` (e.g., `dev` or `prod`).
