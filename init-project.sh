#!/usr/bin/env bash
# b4m-golang-dev project initialization script
#
# This script scaffolds a Golang + Docker Compose + Cloud Run development environment.

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="${SCRIPT_DIR}/templates"
EXAMPLES_DIR="${SCRIPT_DIR}/docs/examples/project-b4m-receipt-process"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
PROJECT_NAME=""
PROJECT_ID=""
REGION="asia-northeast1"
SERVICE_ACCOUNT=""
GITEA_URL=""
GITEA_OWNER=""
GITEA_REPO=""
GITEA_TOKEN=""

# Architecture type / Frontend FW
ARCH_TYPE="monolith_microservice"   # monolith_microservice | spa_bff
FRONTEND_FW=""                      # nuxt | other (only when ARCH_TYPE=spa_bff)

# Service selection flags
USE_POSTGRES=false
USE_MYSQL=false
USE_MARIADB=false
USE_REDIS=false
USE_MINIO=false
USE_FIRESTORE=false

# Output directory
OUTPUT_DIR=""

# Dry-run and housekeeping options
DRY_RUN=false
CLEANUP_TEMPLATES=false
CLEANUP_TEMPLATES_ONLY=false
LANG_CHOICE="en" # default: English prompts; use --lang=ja for Japanese
for arg in "$@"; do
    if [ "$arg" = "--dry-run" ]; then
        DRY_RUN=true
    elif [ "$arg" = "--cleanup-templates" ]; then
        CLEANUP_TEMPLATES=true
    elif [ "$arg" = "--cleanup-templates-only" ]; then
        CLEANUP_TEMPLATES_ONLY=true
    elif [ "$arg" = "--lang=ja" ]; then
        LANG_CHOICE="ja"
    elif [ "$arg" = "--lang=en" ]; then
        LANG_CHOICE="en"
    fi
done

# i18n helper
_choose() {
    # $1=en, $2=ja
    if [ "$LANG_CHOICE" = "ja" ]; then
        printf "%s" "$2"
    else
        printf "%s" "$1"
    fi
}

# Function: remove templates directory
cleanup_templates_dir() {
    if [ "$DRY_RUN" = true ]; then
        info "$(_choose "[DRY-RUN] Will remove templates directory:" "[DRY-RUN] テンプレートディレクトリを削除します:") $TEMPLATES_DIR"
        return 0
    fi
    if confirm "$(_choose "Delete templates/?" "templates/ を削除します。よろしいですか？")" "N"; then
        rm -rf "$TEMPLATES_DIR"
        success "$(_choose "Removed templates/" "templates/ を削除しました")"
    else
        info "$(_choose "Skipped removing templates/" "templates/ の削除をスキップしました")"
    fi
}

# Function: print error message
error() {
    echo -e "${RED}$(_choose "Error" "エラー"): $1${NC}" >&2
    exit 1
}

# Function: print info message
info() {
    echo -e "${BLUE}$(_choose "Info" "情報"): $1${NC}"
}

# Function: print success message
success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Function: print warning message
warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Function: input prompt
prompt() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local var_name="$3"
    local input
    if [ -n "$default_value" ]; then
        read -p "$(echo -e "${BLUE}$prompt_text${NC} [${YELLOW}$default_value${NC}]: ")" input
    else
        read -p "$(echo -e "${BLUE}$prompt_text${NC}: ")" input
    fi
    if [ -z "$input" ]; then
        input="$default_value"
    fi
    eval "$var_name=\"$input\""
}

# Function: Yes/No confirmation
confirm() {
    local prompt_text="$1"
    local default="${2:-N}"
    local response
    if [ "$default" = "Y" ]; then
        read -p "$(echo -e "${BLUE}$prompt_text${NC} [${YELLOW}Y/n${NC}]: ")" response
    else
        read -p "$(echo -e "${BLUE}$prompt_text${NC} [${YELLOW}y/N${NC}]: ")" response
    fi
    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

# Function: validate project name
validate_project_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9-]+$ ]]; then
        error "プロジェクト名は小文字の英数字とハイフンのみ使用可能です"
    fi
    if [ ${#name} -gt 63 ]; then
        error "プロジェクト名は63文字以下である必要があります"
    fi
}

# Function: replace variables in template files
replace_template_vars() {
    local input_file="$1"
    local output_file="$2"
    
    sed -e "s/{project-name}/$PROJECT_NAME/g" \
        -e "s/{project-id}/$PROJECT_ID/g" \
        -e "s/{region}/$REGION/g" \
        -e "s/{service-account}/$SERVICE_ACCOUNT/g" \
        -e "s/{service-name-stg}/${PROJECT_NAME}-stg/g" \
        -e "s/{service-name-prd}/${PROJECT_NAME}-prd/g" \
        "$input_file" > "$output_file"
}

# Function: collect basic information
collect_basic_info() {
    echo ""
    echo "========================================="
    echo "$(_choose "Enter basic information" "基本情報の入力")"
    echo "========================================="
    echo ""
    
    # App / service name
    prompt "$(_choose "Enter app/service name" "アプリ名（サービス名）を入力してください")" "" PROJECT_NAME
    validate_project_name "$PROJECT_NAME"
    
    # GCP Project ID
    echo ""
    echo "$(_choose "GCP Project ID:" "GCPプロジェクトID:")"
    echo "  1. $(_choose "Create new" "新規作成")"
    echo "  2. $(_choose "Choose existing" "既存プロジェクトを選択")"
    local choice
    read -p "$(_choose "Select [1/2]: " "選択 [1/2]: ")" choice
    
    if [ "$choice" = "1" ]; then
        prompt "$(_choose "Enter a new Project ID" "新しいプロジェクトIDを入力してください")" "" PROJECT_ID
        validate_project_name "$PROJECT_ID"
        info "$(_choose "Will create project:" "プロジェクトを作成します:") $PROJECT_ID"
    else
        if [ "$DRY_RUN" = true ]; then
            # In dry-run, skip gcloud calls and ask directly
            prompt "$(_choose "Enter existing GCP Project ID (dry-run)" "既存のGCPプロジェクトIDを入力してください（ドライラン）")" "example-project-id" PROJECT_ID
        else
            # Fetch existing project list
            info "$(_choose "Fetching existing projects..." "既存のプロジェクトを取得中...")"
            local projects
            projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null || echo "")
            
            if [ -z "$projects" ]; then
                error "$(_choose "No existing projects found" "既存のプロジェクトが見つかりません")"
            fi
            
            echo ""
            echo "$(_choose "Available projects:" "利用可能なプロジェクト:")"
            local i=1
            local project_array=()
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    echo "  $i. $line"
                    project_array+=("$line")
                    i=$((i+1))
                fi
            done <<< "$projects"
            
            # Allow number or project ID input
            local selection=""
            prompt "$(_choose "Enter project number or project ID" "プロジェクト番号 または プロジェクトID を入力してください")" "" selection
            # If numeric, treat as number index
            if [[ "$selection" =~ ^[0-9]+$ ]]; then
                local idx=$((selection-1))
                if [ $idx -lt 0 ] || [ $idx -ge ${#project_array[@]} ]; then
                    error "$(_choose "Invalid selection (out of range)" "無効な選択です（番号範囲外）")"
                fi
                PROJECT_ID="${project_array[$idx]}"
            else
                # Search by exact string match
                local found=""
                for pid in "${project_array[@]}"; do
                    if [ "$pid" = "$selection" ]; then
                        found="$pid"
                        break
                    fi
                done
                if [ -z "$found" ]; then
                    error "$(_choose "Invalid selection (no matching project ID)" "無効な選択です（該当するプロジェクトIDがありません）")"
                fi
                PROJECT_ID="$found"
            fi
        fi
    fi
    
    # Region
    prompt "$(_choose "GCP region" "GCPリージョン")" "$REGION" REGION

    # Architecture selection
    echo ""
    echo "$(_choose "Choose architecture:" "アーキテクチャを選択してください:")"
    echo "  1. $(_choose "Monolith/Microservice" "モノリス/マイクロサービス")"
    echo "  2. SPA + BFF ($(_choose "monorepo under" "モノレポ:") frontend/)"
    local arch_choice
    read -p "$(_choose "Select [1/2]: " "選択 [1/2]: ")" arch_choice
    if [ "$arch_choice" = "2" ]; then
        ARCH_TYPE="spa_bff"
        echo ""
        echo "$(_choose "Choose frontend framework:" "フロントエンドFWを選択してください:")"
        echo "  1. Nuxt v3 ($(_choose "recommended" "推奨"))"
        echo "  2. $(_choose "Other (install yourself)" "その他（自分でインストール）")"
        local fe_choice
        read -p "$(_choose "Select [1/2]: " "選択 [1/2]: ")" fe_choice
        if [ "$fe_choice" = "1" ]; then
            FRONTEND_FW="nuxt"
        else
            FRONTEND_FW="other"
        fi
    else
        ARCH_TYPE="monolith_microservice"
    fi
}

# Function: service account setup
setup_service_account() {
    echo ""
    echo "========================================="
    echo "$(_choose "Service Account" "サービスアカウント設定")"
    echo "========================================="
    echo ""
    
    SERVICE_ACCOUNT=""
    if confirm "$(_choose "Create a new service account?" "サービスアカウントを作成しますか？")" "Y"; then
        # Ask user to input SA ID (local part, not email). e.g., my-service
        local default_sa_id="${PROJECT_NAME}-sa"
        local SA_ID=""
        prompt "$(_choose "Enter service account ID (lowercase, digits, hyphen)" "サービスアカウントIDを入力してください（英小文字・数字・ハイフン）")" "$default_sa_id" SA_ID
        # Convert to email address
        SERVICE_ACCOUNT="${SA_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
        echo "$(_choose "Service Account:" "サービスアカウント:") $SERVICE_ACCOUNT"
        if [ "$DRY_RUN" = true ]; then
            info "$(_choose "[DRY-RUN] Create service account:" "[DRY-RUN] サービスアカウントを作成:") $SA_ID ($SERVICE_ACCOUNT)"
        else
            info "$(_choose "Creating service account..." "サービスアカウントを作成中...")"
            gcloud iam service-accounts create "$SA_ID" \
                --display-name="${PROJECT_NAME} Service Account" \
                --project="$PROJECT_ID" 2>/dev/null || warning "サービスアカウントは既に存在する可能性があります"
            success "$(_choose "Service account setup completed" "サービスアカウントの設定が完了しました")"
        fi
    else
        # Ask user to input existing service account email
        prompt "$(_choose "Enter existing service account email (e.g., name@${PROJECT_ID}.iam.gserviceaccount.com)" "既存のサービスアカウントメールを入力してください（例: name@${PROJECT_ID}.iam.gserviceaccount.com）")" "" SERVICE_ACCOUNT
        if [ -z "$SERVICE_ACCOUNT" ]; then
            warning "$(_choose "Service account not specified; permission grants will be skipped/require manual steps" "サービスアカウントが未指定のため、後続の権限付与はスキップ/手動設定が必要です")"
        else
            echo "$(_choose "Service Account:" "サービスアカウント:") $SERVICE_ACCOUNT"
        fi
        info "$(_choose "Using existing service account" "既存のサービスアカウントを使用します")"
    fi
}

# Function: service selection
select_services() {
    echo ""
    echo "========================================="
    echo "$(_choose "Select services to use" "使用するサービスの選択")"
    echo "========================================="
    echo ""
    
    if confirm "Postgres?" "N"; then
        USE_POSTGRES=true
    fi
    
    if confirm "MySQL?" "N"; then
        USE_MYSQL=true
    fi
    
    if confirm "MariaDB?" "N"; then
        USE_MARIADB=true
    fi
    
    if confirm "Redis?" "N"; then
        USE_REDIS=true
    fi
    
    if confirm "$(_choose "MinIO (S3-compatible storage)?" "MinIO (S3互換ストレージ) を使用しますか？")" "N"; then
        USE_MINIO=true
    fi
    
    if confirm "Firestore Emulator?" "N"; then
        USE_FIRESTORE=true
    fi
}

# Function: Gitea settings
setup_gitea() {
    echo ""
    echo "========================================="
    echo "$(_choose "Gitea settings (optional)" "Gitea設定（オプション）")"
    echo "========================================="
    echo ""
    
    if confirm "$(_choose "Configure Gitea Secrets?" "Gitea Secretsを設定しますか？")" "N"; then
        prompt "Gitea URL" "" GITEA_URL
        prompt "$(_choose "Repository owner" "リポジトリ所有者")" "" GITEA_OWNER
        prompt "$(_choose "Repository name" "リポジトリ名")" "" GITEA_REPO
        prompt "$(_choose "Access token" "アクセストークン")" "" GITEA_TOKEN
    fi
}

# Function: configure output directory
setup_output_dir() {
    prompt "$(_choose "Output directory (use '.' for current)" "出力先ディレクトリ（init-project.sh と同じなら '.'）")" "." OUTPUT_DIR
    
    if [ -e "$OUTPUT_DIR" ]; then
        if [ ! -d "$OUTPUT_DIR" ]; then
            error "$(_choose "Output path is not a directory:" "出力先がディレクトリではありません:") $OUTPUT_DIR"
        fi
        # Skip overwrite confirmation when generating under current directory
        if [ "$OUTPUT_DIR" != "." ]; then
            if ! confirm "$(_choose "Directory exists. Overwrite?" "既存のディレクトリです。上書きしますか？")" "N"; then
                error "$(_choose "Aborted" "処理を中断しました")"
            fi
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            info "$(_choose "[DRY-RUN] Create directory:" "[DRY-RUN] ディレクトリを作成:") $OUTPUT_DIR"
        else
            mkdir -p "$OUTPUT_DIR"
            success "$(_choose "Created output directory:" "出力先ディレクトリを作成しました:") $OUTPUT_DIR"
        fi
    fi
}

# Function: create directory structure
create_directory_structure() {
    info "$(_choose "Creating directory structure..." "ディレクトリ構造を作成中...")"
    mkdir -p "$OUTPUT_DIR/app"
    mkdir -p "$OUTPUT_DIR/docker/app"
    mkdir -p "$OUTPUT_DIR/docker/storage"
    if [ "$ARCH_TYPE" = "spa_bff" ]; then
        mkdir -p "$OUTPUT_DIR/frontend"
        mkdir -p "$OUTPUT_DIR/docker/frontend"
    fi
    mkdir -p "$OUTPUT_DIR/scripts"
    mkdir -p "$OUTPUT_DIR/.gitea/workflows"

    # Place .gitkeep in empty directories
    if [ "$DRY_RUN" = true ]; then
        [ "$ARCH_TYPE" = "spa_bff" ] && echo "[DRY-RUN] create $OUTPUT_DIR/frontend/.gitkeep"
        echo "[DRY-RUN] create $OUTPUT_DIR/docker/storage/.gitkeep"
        echo "[DRY-RUN] create $OUTPUT_DIR/.gitea/workflows/.gitkeep"
    else
        if [ "$ARCH_TYPE" = "spa_bff" ]; then
            : > "$OUTPUT_DIR/frontend/.gitkeep"
        fi
        : > "$OUTPUT_DIR/docker/storage/.gitkeep"
        : > "$OUTPUT_DIR/.gitea/workflows/.gitkeep"
    fi
    success "$(_choose "Created directory structure" "ディレクトリ構造を作成しました")"
}

# Function: generate template files
generate_template_files() {
    info "$(_choose "Generating template files..." "テンプレートファイルを生成中...")"
    
    # compose.yml
    replace_template_vars "$TEMPLATES_DIR/compose.yml.template" "$OUTPUT_DIR/compose.yml"
    # Append Frontend (Nuxt) to prod/stg compose
    if [ "$ARCH_TYPE" = "spa_bff" ] && [ "$FRONTEND_FW" = "nuxt" ]; then
        local fe_compose
        fe_compose=$(sed -e "s/{project-name}/$PROJECT_NAME/g" "$TEMPLATES_DIR/services/frontend_nuxt.compose.yml.template")
        printf "\n%s\n" "$fe_compose" >> "$OUTPUT_DIR/compose.yml"
    fi
    
    # compose.override.yml (generated dynamically per selected services)
    generate_compose_override
    
    # Dockerfile
    replace_template_vars "$TEMPLATES_DIR/docker/app/Dockerfile.dev.template" "$OUTPUT_DIR/docker/app/Dockerfile.dev"
    replace_template_vars "$TEMPLATES_DIR/docker/app/Dockerfile.prod.template" "$OUTPUT_DIR/docker/app/Dockerfile.prod"
    
    # Frontend (Nuxt) Dockerfiles
    if [ "$ARCH_TYPE" = "spa_bff" ] && [ "$FRONTEND_FW" = "nuxt" ]; then
        mkdir -p "$OUTPUT_DIR/docker/frontend/nuxt"
        replace_template_vars "$TEMPLATES_DIR/docker/frontend/nuxt/Dockerfile.dev.template" "$OUTPUT_DIR/docker/frontend/nuxt/Dockerfile.dev"
        replace_template_vars "$TEMPLATES_DIR/docker/frontend/nuxt/Dockerfile.stg.template" "$OUTPUT_DIR/docker/frontend/nuxt/Dockerfile.stg"
        replace_template_vars "$TEMPLATES_DIR/docker/frontend/nuxt/Dockerfile.prod.template" "$OUTPUT_DIR/docker/frontend/nuxt/Dockerfile.prod"
        # nginx.conf (for port 3000)
        replace_template_vars "$TEMPLATES_DIR/docker/frontend/nuxt/nginx.conf.template" "$OUTPUT_DIR/docker/frontend/nuxt/nginx.conf"
    fi

    # Firestore Emulator Dockerfile
    if [ "$USE_FIRESTORE" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/docker/storage/Dockerfile.dev.template" "$OUTPUT_DIR/docker/storage/Dockerfile.dev"
    fi
    
    # cloudbuild.yaml
    replace_template_vars "$TEMPLATES_DIR/cloudbuild.yaml.template" "$OUTPUT_DIR/cloudbuild.yaml"
    
    # Makefile
    replace_template_vars "$TEMPLATES_DIR/Makefile.template" "$OUTPUT_DIR/Makefile"
    
    # app/ files
    replace_template_vars "$TEMPLATES_DIR/app/go.mod.template" "$OUTPUT_DIR/app/go.mod"
    replace_template_vars "$TEMPLATES_DIR/app/main.go.template" "$OUTPUT_DIR/app/main.go"

    # frontend scaffold(for otherFW: .gitkeep)
    if [ "$ARCH_TYPE" = "spa_bff" ]; then
        if [ "$FRONTEND_FW" = "other" ]; then
            : > "$OUTPUT_DIR/frontend/.gitkeep"
        fi
    fi
    
    success "$(_choose "Generated template files" "テンプレートファイルを生成しました")"
}

# Function: generate compose.override.yml dynamically
generate_compose_override() {
    local depends_on=""
    local services=""
    local volumes=""
    
    # Build depends_on section
    if [ "$USE_POSTGRES" = true ] || [ "$USE_MYSQL" = true ] || [ "$USE_MARIADB" = true ] || \
       [ "$USE_REDIS" = true ] || [ "$USE_MINIO" = true ] || [ "$USE_FIRESTORE" = true ]; then
        depends_on="    depends_on:"$'\n'
        if [ "$USE_POSTGRES" = true ]; then
            depends_on="${depends_on}      - postgres"$'\n'
        fi
        if [ "$USE_MYSQL" = true ]; then
            depends_on="${depends_on}      - mysql"$'\n'
        fi
        if [ "$USE_MARIADB" = true ]; then
            depends_on="${depends_on}      - mariadb"$'\n'
        fi
        if [ "$USE_REDIS" = true ]; then
            depends_on="${depends_on}      - redis"$'\n'
        fi
        if [ "$USE_MINIO" = true ]; then
            depends_on="${depends_on}      - minio"$'\n'
        fi
        if [ "$USE_FIRESTORE" = true ]; then
            depends_on="${depends_on}      - firestore"$'\n'
        fi
    fi
    
    # Remove trailing newline (empty when no dependencies)
    depends_on=$(echo -n "$depends_on" | sed '$s/\n$//')
    
    # Build services section
    local temp_file=$(mktemp)
    
    if [ "$USE_POSTGRES" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/services/postgres.yml.template" "$temp_file"
        services="${services}$(cat "$temp_file")"$'\n'
        volumes="${volumes}  postgres-data:"$'\n'
    fi
    if [ "$USE_MYSQL" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/services/mysql.yml.template" "$temp_file"
        services="${services}$(cat "$temp_file")"$'\n'
        volumes="${volumes}  mysql-data:"$'\n'
    fi
    if [ "$USE_MARIADB" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/services/mariadb.yml.template" "$temp_file"
        services="${services}$(cat "$temp_file")"$'\n'
        volumes="${volumes}  mariadb-data:"$'\n'
    fi
    if [ "$USE_REDIS" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/services/redis.yml.template" "$temp_file"
        services="${services}$(cat "$temp_file")"$'\n'
    fi
    if [ "$USE_MINIO" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/services/minio.yml.template" "$temp_file"
        services="${services}$(cat "$temp_file")"$'\n'
        volumes="${volumes}  minio-data:"$'\n'
    fi
    if [ "$USE_FIRESTORE" = true ]; then
        replace_template_vars "$TEMPLATES_DIR/services/firestore.yml.template" "$temp_file"
        services="${services}$(cat "$temp_file")"$'\n'
        volumes="${volumes}  firestore-data:"$'\n'
    fi
    # Frontend (Nuxt) dev service injection
    if [ "$ARCH_TYPE" = "spa_bff" ] && [ "$FRONTEND_FW" = "nuxt" ]; then
        local fe_dev
        fe_dev=$(sed -e "s/{project-name}/$PROJECT_NAME/g" "$TEMPLATES_DIR/services/frontend_nuxt.override.yml.template")
        services="${services}${fe_dev}"$'\n'
    fi
    
    rm -f "$temp_file"
    
    # Generate compose.override.yml (BSD sed-safe insertion)
    local dep_file svc_file vol_file tmp_template tmp_output
    dep_file=$(mktemp)
    svc_file=$(mktemp)
    vol_file=$(mktemp)
    tmp_template=$(mktemp)
    tmp_output=$(mktemp)

    printf "%s\n" "$depends_on" > "$dep_file"
    printf "%s\n" "$services" > "$svc_file"
    printf "%s\n" "$volumes" > "$vol_file"
    
    # Resolve single-line variables first
    sed -e "s/{project-name}/$PROJECT_NAME/g" \
        -e "s/{project-id}/$PROJECT_ID/g" \
        -e "s/{region}/$REGION/g" \
        -e "s/{service-account}/$SERVICE_ACCOUNT/g" \
        "$TEMPLATES_DIR/compose.override.yml.template" > "$tmp_template"

    # Insert multi-line blocks via awk (BSD-compatible)
    awk -v depf="$dep_file" -v svcf="$svc_file" -v volf="$vol_file" '
      {
        if (index($0, "{SERVICE_DEPENDS_ON}")) {
          while ((getline line < depf) > 0) print line; close(depf); next
        }
        if (index($0, "{SERVICES}")) {
          while ((getline line < svcf) > 0) print line; close(svcf); next
        }
        if (index($0, "{VOLUMES}")) {
          while ((getline line < volf) > 0) print line; close(volf); next
        }
        print
      }
    ' "$tmp_template" > "$tmp_output"

    mv "$tmp_output" "$OUTPUT_DIR/compose.override.yml"
    rm -f "$dep_file" "$svc_file" "$vol_file" "$tmp_template"
}

# Function: generate script files
generate_scripts() {
    info "$(_choose "Generating scripts..." "スクリプトファイルを生成中...")"
    
    # Scripts generated from templates
    if [ -f "$TEMPLATES_DIR/scripts/cloudrun-init.sh.template" ]; then
        replace_template_vars "$TEMPLATES_DIR/scripts/cloudrun-init.sh.template" "$OUTPUT_DIR/scripts/cloudrun-init.sh"
        chmod +x "$OUTPUT_DIR/scripts/cloudrun-init.sh"
    fi
    
    if [ -f "$TEMPLATES_DIR/scripts/grant-cloud-build-permissions.sh.template" ]; then
        replace_template_vars "$TEMPLATES_DIR/scripts/grant-cloud-build-permissions.sh.template" "$OUTPUT_DIR/scripts/grant-cloud-build-permissions.sh"
        chmod +x "$OUTPUT_DIR/scripts/grant-cloud-build-permissions.sh"
    fi
    if [ "$ARCH_TYPE" = "spa_bff" ] && [ "$FRONTEND_FW" = "nuxt" ]; then
        if [ -f "$TEMPLATES_DIR/scripts/frontend-init.sh.template" ]; then
            replace_template_vars "$TEMPLATES_DIR/scripts/frontend-init.sh.template" "$OUTPUT_DIR/scripts/frontend-init.sh"
            chmod +x "$OUTPUT_DIR/scripts/frontend-init.sh"
        fi
    fi
    
    # Scripts copied from templates/examples with variable substitution
    local scripts_to_copy=(
        "enable-required-apis.sh"
        "diagnose-cloud-build.sh"
        "set-gitea-secrets.sh"
        "vulncheck.sh"
        "cloudrun-apply-env.sh"
        "cloudrun-apply-env-prod.sh"
        "cloudrun-init.sh" # Fallback (do not overwrite if generated from template)
        "create-env-example.sh"
    )

    local fallback_examples_dir="${SCRIPT_DIR}/docs/examples/project-b4m-corp-num-api"
    
    for script in "${scripts_to_copy[@]}"; do
        local src=""
        # 1) prefer templates/scripts
        if [ -f "$TEMPLATES_DIR/scripts/$script.template" ]; then
            src="$TEMPLATES_DIR/scripts/$script.template"
        # 2) examples (receipt-process)
        elif [ -f "$EXAMPLES_DIR/scripts/$script" ]; then
            src="$EXAMPLES_DIR/scripts/$script"
        # 3) examples (corp-num-api)
        elif [ -f "$fallback_examples_dir/scripts/$script" ]; then
            src="$fallback_examples_dir/scripts/$script"
        else
            warning "スクリプトが見つかりませんでした: $script"
            continue
        fi
        # Do not overwrite scripts already generated from templates (e.g., cloudrun-init)
        if [ -f "$OUTPUT_DIR/scripts/$script" ]; then
            continue
        fi
        info "$(_choose "Add script:" "スクリプトを追加:") $script"
        replace_template_vars "$src" "$OUTPUT_DIR/scripts/$script"
        chmod +x "$OUTPUT_DIR/scripts/$script"
    done
    
    # Replace service account names in scripts
    find "$OUTPUT_DIR/scripts" -type f -name "*.sh" -exec sed -i.bak \
        -e "s/b4m-receipt-process/$PROJECT_NAME/g" \
        -e "s/b4m-corp-num-api/$PROJECT_NAME/g" {} \;
    find "$OUTPUT_DIR/scripts" -type f -name "*.bak" -delete
    
    success "$(_choose "Generated scripts" "スクリプトファイルを生成しました")"
}

# Function: generate .env.example
generate_env_example() {
    info "$(_choose "Generating .env.example..." ".env.exampleを生成中...")"
    
    cat > "$OUTPUT_DIR/.env.example" << EOF
# Google Cloud
GOOGLE_CLOUD_PROJECT=$PROJECT_ID
GCP_REGION=$REGION

# API keys
CLOUDRUN_API_KEY=your-api-key-here
EOF

    # Append per-service environment variables
    if [ "$USE_POSTGRES" = true ]; then
        cat >> "$OUTPUT_DIR/.env.example" << EOF

# Postgres
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=appdb
EOF
    fi
    
    if [ "$USE_MYSQL" = true ]; then
        cat >> "$OUTPUT_DIR/.env.example" << EOF

# MySQL
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=appdb
MYSQL_USER=appuser
MYSQL_PASSWORD=apppassword
EOF
    fi
    
    if [ "$USE_MARIADB" = true ]; then
        cat >> "$OUTPUT_DIR/.env.example" << EOF

# MariaDB
MARIADB_HOST=mariadb
MARIADB_PORT=3306
MARIADB_ROOT_PASSWORD=rootpassword
MARIADB_DATABASE=appdb
MARIADB_USER=appuser
MARIADB_PASSWORD=apppassword
EOF
    fi
    
    if [ "$USE_REDIS" = true ]; then
        cat >> "$OUTPUT_DIR/.env.example" << EOF

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
EOF
    fi
    
    if [ "$USE_MINIO" = true ]; then
        cat >> "$OUTPUT_DIR/.env.example" << EOF

# MinIO (S3-compatible storage)
GCS_EMULATOR_HOST=minio:9000
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
STORAGE_BUCKET_NAME=your-bucket-name
STORAGE_USE_SSL=false
EOF
    fi
    
    if [ "$USE_FIRESTORE" = true ]; then
        cat >> "$OUTPUT_DIR/.env.example" << EOF

# Firestore Emulator
FIRESTORE_EMULATOR_HOST=firestore:8081
FIRESTORE_COLLECTION_NAME=your-collection
EOF
    fi
    
    cat >> "$OUTPUT_DIR/.env.example" << EOF

# App config
CACHE_TTL=2160h
LOG_LEVEL=INFO

# Local dev (optional)
SERVER_PORT=8080
EOF
    
    success "$(_choose "Generated .env.example" ".env.exampleを生成しました")"
}

# Function: generate Gitea workflow
generate_gitea_workflow() {
    info "$(_choose "Generating Gitea workflow..." "Gitea workflowを生成中...")"
    
    if [ -f "$EXAMPLES_DIR/.gitea/workflows/deploy.yml" ]; then
        replace_template_vars "$EXAMPLES_DIR/.gitea/workflows/deploy.yml" "$OUTPUT_DIR/.gitea/workflows/deploy.yml"
        
        # Replace service names
        sed -i.bak \
            -e "s/b4m-receipt-process/$PROJECT_NAME/g" \
            -e "s/b4m-receipt-process-stg/${PROJECT_NAME}-stg/g" \
            -e "s/b4m-receipt-process-prd/${PROJECT_NAME}-prd/g" \
            "$OUTPUT_DIR/.gitea/workflows/deploy.yml"
        rm -f "$OUTPUT_DIR/.gitea/workflows/deploy.yml.bak"
    fi
    
    success "$(_choose "Generated Gitea workflow" "Gitea workflowを生成しました")"
}

# Function: main file generation routine
generate_files() {
    info "$(_choose "Starting file generation..." "ファイル生成を開始します...")"
    if [ "$DRY_RUN" = true ]; then
        local PFX="$OUTPUT_DIR"
        [ "$PFX" = "." ] && PFX="."
        echo "[DRY-RUN] $(_choose "The following files/directories would be generated:" "次のファイル/ディレクトリが生成されます:")"
        echo "  - $PFX/compose.yml"
        echo "  - $PFX/compose.override.yml"
        echo "  - $PFX/docker/app/Dockerfile.dev"
        echo "  - $PFX/docker/app/Dockerfile.prod"
        if [ "$USE_FIRESTORE" = true ]; then
            echo "  - $PFX/docker/storage/Dockerfile.dev"
        fi
        echo "  - $PFX/docker/storage/.gitkeep"
        if [ "$ARCH_TYPE" = "spa_bff" ] && [ "$FRONTEND_FW" = "nuxt" ]; then
            echo "  - $PFX/docker/frontend/nuxt/Dockerfile.dev"
            echo "  - $PFX/docker/frontend/nuxt/Dockerfile.stg"
            echo "  - $PFX/docker/frontend/nuxt/Dockerfile.prod"
        fi
        if [ "$ARCH_TYPE" = "spa_bff" ]; then
            echo "  - $PFX/frontend/.gitkeep"
        fi
        echo "  - $PFX/cloudbuild.yaml"
        echo "  - $PFX/Makefile"
        echo "  - $PFX/app/go.mod"
        echo "  - $PFX/app/main.go"
        echo "  - $PFX/scripts/*.sh ($(_choose "all" "一式"))"
        echo "  - $PFX/.gitea/workflows/deploy.yml"
        echo "  - $PFX/.gitea/workflows/.gitkeep"
        echo "[DRY-RUN] $(_choose "Additional services:" "追加サービス:")"
        [ "$USE_POSTGRES" = true ] && echo "    - Postgres"
        [ "$USE_MYSQL" = true ] && echo "    - MySQL"
        [ "$USE_MARIADB" = true ] && echo "    - MariaDB"
        [ "$USE_REDIS" = true ] && echo "    - Redis"
        [ "$USE_MINIO" = true ] && echo "    - MinIO"
        [ "$USE_FIRESTORE" = true ] && echo "    - Firestore Emulator"
        success "$(_choose "Dry-run output completed (no files were created)" "ドライランの出力を完了しました（実ファイルは生成していません）")"
        return 0
    fi

    create_directory_structure
    generate_template_files
    generate_scripts
    generate_env_example
    generate_gitea_workflow
    
    success "$(_choose "All files generated" "すべてのファイルを生成しました")"

    # Templates cleanup
    if [ "$CLEANUP_TEMPLATES" = true ]; then
        if [ "$DRY_RUN" = true ]; then
            info "$(_choose "[DRY-RUN] Will remove templates directory:" "[DRY-RUN] テンプレートディレクトリを削除します:") $TEMPLATES_DIR"
        else
            echo ""
            if confirm "$(_choose "Delete templates/?" "templates/ を削除します。よろしいですか？")" "N"; then
                rm -rf "$TEMPLATES_DIR"
                success "$(_choose "Removed templates/" "templates/ を削除しました")"
            else
                info "$(_choose "Skipped removing templates/" "templates/ の削除をスキップしました")"
            fi
        fi
    fi
}

# Entry point
main() {
    echo "========================================="
    echo "$(_choose "b4m-golang-dev Project Initialization" "b4m-golang-dev プロジェクト初期化")"
    echo "========================================="
    echo ""

    # Templates-only cleanup mode
    if [ "$CLEANUP_TEMPLATES_ONLY" = true ]; then
        cleanup_templates_dir
        return 0
    fi
    
    # Dependency checks
    if ! command -v gcloud &> /dev/null; then
        error "$(_choose "gcloud CLI is not installed" "gcloud CLI がインストールされていません")"
    fi
    
    if ! command -v docker &> /dev/null; then
        error "$(_choose "docker is not installed" "docker がインストールされていません")"
    fi
    
    # Basic info
    collect_basic_info
    
    # Output directory
    setup_output_dir
    
    # Service account
    setup_service_account
    
    # Service selection
    select_services
    
    # Gitea settings
    setup_gitea
    
    echo ""
    echo "========================================="
    echo "$(_choose "Review settings" "設定確認")"
    echo "========================================="
    echo "$(_choose "App name" "アプリ名"): $PROJECT_NAME"
    echo "GCP Project ID: $PROJECT_ID"
    echo "$(_choose "Region" "リージョン"): $REGION"
    echo "$(_choose "Service Account" "サービスアカウント"): $SERVICE_ACCOUNT"
    echo "$(_choose "Output" "出力先"): $OUTPUT_DIR"
    echo ""
    
    if ! confirm "$(_choose "Proceed with these settings?" "この設定で続行しますか？")" "Y"; then
        error "$(_choose "Aborted" "処理を中断しました")"
    fi
    
    # Generate files
    generate_files
    
    success "$(_choose "Initialization completed!" "初期化が完了しました！")"
    echo ""
    echo "$(_choose "Next steps:" "次のステップ:")"
    echo "  1. cd $OUTPUT_DIR"
    echo "  2. ./scripts/enable-required-apis.sh $PROJECT_ID"
    echo "  3. ./scripts/grant-cloud-build-permissions.sh $PROJECT_ID"
    if [ -n "$GITEA_URL" ]; then
        echo "  4. ./scripts/set-gitea-secrets.sh $GITEA_URL $GITEA_OWNER $GITEA_REPO $GITEA_TOKEN"
    fi
}

# Execute script
main "$@"

