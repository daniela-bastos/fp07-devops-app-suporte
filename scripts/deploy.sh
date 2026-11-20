
#!/usr/bin/env bash
set -Eeuo pipefail

# Diretório principal do projeto
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# Configuração
ENV_FILE="config/.env.prod"
COMPOSE_FILE="compose.yaml"
PROJECT_NAME="fp07-prod"

TARGET_VERSION="${1:-}"
STABLE_VERSION="${2:-}"

ALLOW_ROLLBACK="${ALLOW_ROLLBACK:-false}"
SIMULATE_DEPLOY_FAILURE="${SIMULATE_DEPLOY_FAILURE:-false}"

# Validação dos argumentos
if [[ -z "$TARGET_VERSION" || -z "$STABLE_VERSION" ]]; then
    echo "[ERRO] Indica a versão pretendida e a versão estável."
    echo "Uso: bash scripts/deploy.sh <nova_versao> <versao_estavel>"
    exit 2
fi

if [[ ! "$TARGET_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ||
      ! "$STABLE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERRO] Formato de versão inválido."
    exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
    echo "[ERRO] Ficheiro $ENV_FILE não encontrado."
    exit 2
fi

if [[ "$ALLOW_ROLLBACK" != "true" &&
      "$ALLOW_ROLLBACK" != "false" ]]; then
    echo "[ERRO] ALLOW_ROLLBACK deve ser true ou false."
    exit 2
fi

# Comando Compose base
compose() {
    docker compose \
        -f "$COMPOSE_FILE" \
        --env-file "$ENV_FILE" \
        -p "$PROJECT_NAME" "$@"
}

echo "=================================="
echo "Deployment - App Suporte"
echo "Nova versão: $TARGET_VERSION"
echo "Versão estável: $STABLE_VERSION"
echo "Rollback autorizado: $ALLOW_ROLLBACK"
echo "=================================="

# Verificar Docker e configuração
docker info >/dev/null
compose config --quiet

# Deployment da nova versão
echo "[INFO] A instalar a versão $TARGET_VERSION..."

deployment_ok=true

if [[ "$SIMULATE_DEPLOY_FAILURE" == "true" ]]; then
    echo "[INFO] Aplicar configuração de falha..."
    if ! APP_VERSION="$TARGET_VERSION" docker compose \
        -f compose.yaml \
        -f compose.failure.yaml \
        --env-file "$ENV_FILE" \
        -p "$PROJECT_NAME" \
        up -d --pull always \
        --force-recreate --wait --wait-timeout 90; then
        deployment_ok=false
    fi
else
    if ! APP_VERSION="$TARGET_VERSION" compose \
        up -d --pull always \
        --force-recreate --wait --wait-timeout 90; then
        deployment_ok=false
    fi
fi

# Validação funcional
if [[ "$deployment_ok" == "true" ]]; then
    echo "[INFO] A executar smoke tests..."

    if bash scripts/smoke-test.sh; then
        echo "[SUCESSO] Deployment validado."
        exit 0
    fi
fi

echo "[ERRO] Deployment da versão $TARGET_VERSION falhou."

# Rollback condicionado à autorização
if [[ "$ALLOW_ROLLBACK" != "true" ]]; then
    echo "[AVISO] Rollback não autorizado."
    exit 1
fi

echo "[INFO] A recuperar a versão $STABLE_VERSION..."

if ! APP_VERSION="$STABLE_VERSION" compose \
    up -d --pull always \
    --force-recreate --wait --wait-timeout 90; then
    echo "[ERRO] Falha na recuperação."
    exit 1
fi

echo "[INFO] A validar a recuperação..."

if bash scripts/smoke-test.sh; then
    echo "[RECUPERADO] Serviço restabelecido."
    echo "[FALHA] A nova release não foi aprovada."
    exit 1
else
    echo "[ERRO] Recuperação não validada."
    exit 1
fi
