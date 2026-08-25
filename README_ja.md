# d4run

[![CI](https://github.com/b4moss/d4run/actions/workflows/ci.yml/badge.svg)](https://github.com/b4moss/d4run/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/codecov/c/github/b4moss/d4run)](https://codecov.io/gh/b4moss/d4run)
[![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://github.com/b4moss/d4run)
[![Release](https://img.shields.io/github/v/release/b4moss/d4run)](https://github.com/b4moss/d4run/releases)
[![License](https://img.shields.io/github/license/b4moss/d4run)](https://github.com/b4moss/d4run/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/b4moss/d4run/badge)](https://securityscorecards.dev/viewer/?uri=github.com/b4moss/d4run)

Golang + Docker Compose + CloudRun の開発環境を迅速に構築するための雛形生成ツールです。

[English version is here.](./README.md)

## 概要

このプロジェクトは、合同会社知的・自転車が、Webアプリケーションを開発する時に使用する雛形を自動生成します。
当社が、特によく使うスタックを中心に、環境構築の速度を上げることが目的です。

## 機能

- 対話式スクリプトでプロジェクト初期化を自動化
- Docker Compose設定の自動生成（選択可能なサービス: Postgres、MySQL、MariaDB、Redis、MinIO、Firestore Emulator）
- CloudRun用の設定ファイル（Cloud Build、Gitea Actions）の自動生成
- 各種スクリプト（API有効化、権限付与、デプロイ等）の自動生成

## 前提条件

以下のツールがインストールされている必要があります:

- `gcloud` CLI（Google Cloud SDK）
- `docker` / `docker compose`
- `bash` 4.0+ または `zsh` 5.0+（macOSユーザーはzsh推奨）

## 使い方

### 1. プロジェクトの初期化

```bash
./init-project.sh [--dry-run] [--cleanup-templates] [--cleanup-templates-only]
```

対話式で以下の情報を入力します:

1. **アプリ名（サービス名）**（例: `b4m-receipt-process`）
2. **GCPプロジェクトID**: 新規作成 or 既存選択
3. **リージョン**: デフォルト `asia-northeast1`
4. **サービスアカウント**: 作成 or 既存選択
5. **使用するサービス**: Postgres、MySQL、MariaDB、Redis、MinIO、Firestore Emulator から選択
6. **Gitea設定**: オプション（URL、リポジトリ所有者、リポジトリ名、アクセストークン）

### オプション

- `--dry-run`: 外部コマンドやファイル生成を行わず、生成予定のみを表示
- `--cleanup-templates`: 生成完了後に `templates/` を削除（要確認）
- `--cleanup-templates-only`: 生成処理は行わず、`templates/` の削除のみ実行（`--dry-run` と併用可能）

### 2. 生成されたプロジェクトのセットアップ

生成されたプロジェクトディレクトリに移動し、以下のスクリプトを実行します:

```bash
cd <project-name>

# 必要なAPIを有効化
./scripts/enable-required-apis.sh <PROJECT_ID>

# Cloud Build権限を付与
./scripts/grant-cloud-build-permissions.sh <PROJECT_ID>

# Gitea Secretsを設定（オプション）
./scripts/set-gitea-secrets.sh <GITEA_URL> <OWNER> <REPO> <TOKEN>

### SPA + BFF を選んだ場合

- フロントFW選択で「Nuxt v3」を選ぶと、次が生成されます:
  - `frontend/` ディレクトリ
  - `docker/frontend/nuxt/Dockerfile.dev|stg|prod`
  - `compose.yml` に `frontend`（本番/検証）
  - `compose.override.yml` に `frontend`（開発）
  - `scripts/frontend-init.sh`（Nuxt 3 初期化スクリプト）

- 初回は以下を実行してNuxt 3（v3系最新）を初期化:

```bash
cd <project-name>
./scripts/frontend-init.sh
```

- ローカル開発（BFFと同時起動）:

```bash
docker compose -f compose.yml -f compose.override.yml up -d
```

- 備考: 本番は最終的にGCS等のオブジェクトストレージにデプロイします（Dockerfile.stg/prodは検証用途）。
```

### 3. 開発環境の起動

```bash
# 事前に環境変数ファイルを用意（手動）
# リポジトリに用意した例からコピーして編集
cp .env.example .env

# Docker Composeで開発環境を起動
docker compose -f compose.yml -f compose.override.yml up -d

# または Makefile を使用
make up
```

## 生成されるファイル構成

```
<project-name>/
├── app/                          # Goアプリケーションコード
│   ├── go.mod
│   ├── go.sum
│   └── main.go
├── docker/
│   ├── app/
│   │   ├── Dockerfile.dev       # 開発用（Airホットリロード）
│   │   └── Dockerfile.prod      # 本番用（マルチステージビルド）
│   └── storage/                 # Firestore Emulator（選択時のみ）
│       └── Dockerfile.dev
├── scripts/                      # 各種スクリプト
│   ├── create-env-example.sh
│   ├── cloudrun-init.sh
│   ├── cloudrun-apply-env.sh
│   ├── cloudrun-apply-env-prod.sh
│   ├── enable-required-apis.sh
│   ├── grant-cloud-build-permissions.sh
│   ├── set-gitea-secrets.sh
│   ├── diagnose-cloud-build.sh
│   └── vulncheck.sh
├── compose.yml                   # 本番用Docker Compose設定
├── compose.override.yml          # 開発用Docker Compose設定
├── cloudbuild.yaml               # Cloud Build設定
├── Makefile                      # Docker Compose操作ヘルパー
├── .env.example                  # 環境変数テンプレート
└── .gitea/
    └── workflows/
        └── deploy.yml            # Gitea Actions ワークフロー
```

## スタック

- **バックエンド**: golang 1.24
- **データベース**: Postgres / MySQL / MariaDB（選択可能）
- **インメモリキャッシュ**: Redis（選択可能）
- **ストレージ**: MinIO（開発環境用、選択可能）
- **Firestore**: Firestore Emulator（開発環境用、選択可能）
- **インフラ**: CloudRun（stg/prod）

## 詳細仕様

詳細な仕様については、[docs/specs-detail.md](docs/specs-detail.md) を参照してください。

## ライセンス

このプロジェクトは、MIT Licenseです。

