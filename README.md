# d4run

[![CI](https://github.com/b4moss/d4run/actions/workflows/ci.yml/badge.svg)](https://github.com/b4moss/d4run/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/b4moss/d4run)](https://codecov.io/gh/b4moss/d4run)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://github.com/b4moss/d4run)
[![Release](https://img.shields.io/github/v/release/b4moss/d4run)](https://github.com/b4moss/d4run/releases)
[![License](https://img.shields.io/github/license/b4moss/d4run)](https://github.com/b4moss/d4run/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/b4moss/d4run/badge)](https://securityscorecards.dev/viewer/?uri=github.com/b4moss/d4run)

A scaffolding generator to quickly spin up a Golang + Docker Compose + Cloud Run development environment.

[日本語版はこちら](./README_ja.md)

## Overview

This project automatically generates a template we use at CHITEKI JITENSHA LLC for building web applications. It focuses on the stacks we use most often to accelerate environment setup.

## Features

- Interactive script to automate project initialization
- Auto-generate Docker Compose configuration (optional services: Postgres, MySQL, MariaDB, Redis, MinIO, Firestore Emulator)
- Auto-generate configuration for Cloud Run (Cloud Build, Gitea Actions)
- Auto-generate helper scripts (enable APIs, grant permissions, deploy, etc.)

## Prerequisites

Please install the following tools:

- `gcloud` CLI (Google Cloud SDK)
- `docker` / `docker compose`
- `bash` 4.0+ or `zsh` 5.0+ (zsh recommended on macOS)

## Usage

### 1. Initialize a project

```bash
./init-project.sh [--dry-run] [--cleanup-templates] [--cleanup-templates-only]
```

You will be asked interactively for:

1. **App/Service name** (e.g., `b4m-receipt-process`)
2. **GCP Project ID**: create new or pick existing
3. **Region**: default `asia-northeast1`
4. **Service Account**: create new or use existing
5. **Services to use**: select from Postgres, MySQL, MariaDB, Redis, MinIO, Firestore Emulator
6. **Gitea settings**: optional (URL, owner, repo, access token)

### Options

- `--dry-run`: do not run external commands or write files; show what would be generated
- `--cleanup-templates`: delete `templates/` after generation (with confirmation)
- `--cleanup-templates-only`: delete `templates/` only (can be combined with `--dry-run`)

### 2. Set up the generated project

Move into the generated directory and run the scripts below:

```bash
cd <project-name>

# Enable required GCP APIs
./scripts/enable-required-apis.sh <PROJECT_ID>

# Grant Cloud Build permissions
./scripts/grant-cloud-build-permissions.sh <PROJECT_ID>

# Configure Gitea Secrets (optional)
./scripts/set-gitea-secrets.sh <GITEA_URL> <OWNER> <REPO> <TOKEN>

### If you chose SPA + BFF

- When choosing "Nuxt v3" as the frontend framework, the following will be generated:
  - `frontend/` directory
  - `docker/frontend/nuxt/Dockerfile.dev|stg|prod`
  - `compose.yml` includes `frontend` (prod/stg)
  - `compose.override.yml` includes `frontend` (dev)
  - `scripts/frontend-init.sh` (Nuxt 3 initializer)

- Initialize Nuxt 3 (latest v3) on the first run:

```bash
cd <project-name>
./scripts/frontend-init.sh
```

- Local development (run BFF and frontend together):

```bash
docker compose -f compose.yml -f compose.override.yml up -d
```

- Note: For production, deploy the SPA to an object storage such as GCS. `Dockerfile.stg/prod` are intended for verification.
```

### 3. Start the development environment

```bash
# Prepare environment vars (manually)
# Copy the example file and edit it
cp .env.example .env

# Start with Docker Compose
docker compose -f compose.yml -f compose.override.yml up -d

# Or use Makefile helpers
make up
```

## Generated file structure

```
<project-name>/
├── app/                          # Go application code
│   ├── go.mod
│   ├── go.sum
│   └── main.go
├── docker/
│   ├── app/
│   │   ├── Dockerfile.dev       # Development (Air hot reload)
│   │   └── Dockerfile.prod      # Production (multi-stage build)
│   └── storage/                 # Firestore Emulator (when selected)
│       └── Dockerfile.dev
├── scripts/                      # Helper scripts
│   ├── create-env-example.sh
│   ├── cloudrun-init.sh
│   ├── cloudrun-apply-env.sh
│   ├── cloudrun-apply-env-prod.sh
│   ├── enable-required-apis.sh
│   ├── grant-cloud-build-permissions.sh
│   ├── set-gitea-secrets.sh
│   ├── diagnose-cloud-build.sh
│   └── vulncheck.sh
├── compose.yml                   # Docker Compose for prod
├── compose.override.yml          # Docker Compose for dev
├── cloudbuild.yaml               # Cloud Build config
├── Makefile                      # Docker Compose helpers
├── .env.example                  # Environment variable template
└── .gitea/
    └── workflows/
        └── deploy.yml            # Gitea Actions workflow
```

## Stack

- **Backend**: golang 1.24
- **Databases**: Postgres / MySQL / MariaDB (optional)
- **In-memory cache**: Redis (optional)
- **Storage**: MinIO (for local dev, optional)
- **Firestore**: Firestore Emulator (for local dev, optional)
- **Infrastructure**: Cloud Run (stg/prod)

## Detailed Specs

For more details, see `docs/specs-detail.md`.

## License

This project is licensed under the MIT License.
