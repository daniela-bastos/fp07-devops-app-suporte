
#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${BASE_URL:-http://localhost:8003}"

failed=0

echo "=================================="
echo "Smoke Tests - App Suporte"
echo "URL: $BASE_URL"
echo "=================================="

for endpoint in /health /ready /api/status; do
    echo ""
    echo "A verificar $endpoint..."

    if http_code=$(curl -s -o /dev/null \
        -w "%{http_code}" \
        --max-time 10 \
        "${BASE_URL}${endpoint}"); then

        if [[ "$http_code" == "200" ]]; then
            echo "[OK] $endpoint - HTTP $http_code"
        else
            echo "[ERRO] $endpoint - HTTP $http_code"
            failed=1
        fi

    else
        echo "[ERRO] $endpoint - Falha de ligação"
        failed=1
    fi
done

echo ""
echo "=================================="

if [[ "$failed" -eq 0 ]]; then
    echo "[SUCESSO] Todos os testes passaram."
    exit 0
else
    echo "[FALHA] Foram detetados erros."
    exit 1
fi
