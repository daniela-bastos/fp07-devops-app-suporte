# FP07 — DevOps | App Suporte

**Natixis — Support & Engineering Stream · Prática Laboratorial 07**

Repositório: https://github.com/daniela-bastos/fp07-devops-app-suporte

## 1. Objetivo e pré-requisitos

Construir e publicar uma API FastAPI em imagens Docker versionadas; instalar com Docker Compose; monitorizar health checks; executar smoke tests; diagnosticar uma regressão funcional e recuperar uma versão estável. Como extensão, automatizar o processo com Bash e Jenkins.

**Pré-requisitos:** Docker Desktop/Engine, Docker Compose v2, Git, Bash, curl, acesso ao Docker Hub; Jenkins e agente com acesso a Docker para o Desafio B. No Windows, usar Git Bash ou WSL2. Executar os comandos na raiz `app-suporte/`.

```bash
docker --version
docker compose version
docker info
git --version
bash --version
curl --version
```

### Estrutura

```text
app-suporte/
├── main.py
├── requirements.txt
├── Dockerfile
├── compose.yaml
├── compose.failure.yaml
├── Jenkinsfile
├── .dockerignore
├── .gitignore
├── .gitattributes
├── config/
│   ├── .env.prod.example
│   └── .env.jenkins.example
├── scripts/
│   ├── deploy.sh
│   └── smoke-test.sh
└── README.md
```

Os ficheiros reais `config/.env.prod` e `config/.env.jenkins` são locais, ignorados pelo Git e **não devem ser publicados**. Os exemplos não contêm credenciais.

## 2. Construção das imagens

```bash
docker build -t app-suporte:1.0.0 .
docker build -t app-suporte:1.1.0 .
docker image ls app-suporte
```

As tags `1.0.0` e `1.1.0` foram publicadas para o laboratório. A falha da versão `1.1.0` é **simulada por configuração** (`SIMULATE_FAILURE=true`), através de `compose.failure.yaml`, e não por uma diferença obrigatória no código da imagem.

## 3. Publicação e recuperação do registry

```bash
docker tag app-suporte:1.0.0 danielabastos/app-suporte:1.0.0
docker tag app-suporte:1.1.0 danielabastos/app-suporte:1.1.0
# Autenticar apenas se necessário para publicar; nunca incluir credenciais no README.
docker login
docker push danielabastos/app-suporte:1.0.0
docker push danielabastos/app-suporte:1.1.0

docker pull danielabastos/app-suporte:1.0.0
docker pull danielabastos/app-suporte:1.1.0
```

Imagens: https://hub.docker.com/r/danielabastos/app-suporte

## 4. Configuração e deployment

Preparar a configuração local (não versionar o ficheiro resultante):

```bash
cp config/.env.prod.example config/.env.prod
```

O exemplo define `IMAGE_REPO=docker.io/danielabastos/app-suporte`, `APP_VERSION=1.0.0`, `APP_ENV=production`, `LOG_LEVEL=WARNING` e `HOST_PORT=8003`.

```bash
APP_VERSION=1.0.0 docker compose -f compose.yaml \
  --env-file config/.env.prod -p fp07-prod config --quiet

APP_VERSION=1.0.0 docker compose -f compose.yaml \
  --env-file config/.env.prod -p fp07-prod pull api

APP_VERSION=1.0.0 docker compose -f compose.yaml \
  --env-file config/.env.prod -p fp07-prod \
  up -d --pull always --force-recreate --wait --wait-timeout 90
```

A API fica acessível no host em `http://localhost:8003` (porta interna 8000).

## 5. Validação funcional

```bash
docker compose -f compose.yaml -p fp07-prod ps
docker compose -f compose.yaml -p fp07-prod logs --tail=50 api
curl -i http://localhost:8003/health
curl -i http://localhost:8003/ready
curl -i http://localhost:8003/api/status
bash scripts/smoke-test.sh
```

| Endpoint | Finalidade | Estado funcional |
|---|---|---|
| `/health` | API responde | HTTP 200 |
| `/ready` | API pronta | HTTP 200 |
| `/api/status` | Estado e versão | HTTP 200, versão `1.0.0` |

O script `scripts/smoke-test.sh` usa `BASE_URL` (por omissão `http://localhost:8003`), testa os três endpoints e termina com código 0 se todos devolverem 200; caso contrário termina com código 1.

## 6. Reproduzir a falha funcional

A regressão é provocada pela configuração adicional `compose.failure.yaml`, que define `SIMULATE_FAILURE=true`.

```bash
APP_VERSION=1.1.0 docker compose \
  -f compose.yaml -f compose.failure.yaml \
  --env-file config/.env.prod -p fp07-prod \
  up -d --pull always --force-recreate --wait --wait-timeout 90

curl -i http://localhost:8003/health
curl -i http://localhost:8003/ready
curl -i http://localhost:8003/api/status
bash scripts/smoke-test.sh

docker compose -f compose.yaml -p fp07-prod logs --tail=100 api
```

**Resultado observado:** `/health` permanece em HTTP 200, mas `/ready` e `/api/status` devolvem HTTP 503. Assim, o healthcheck pode indicar `healthy` apesar de existir uma falha funcional. Os smoke tests detetam a regressão.

## 7. Rollback e recuperação

### Manual

Remover a sobreposição de falha e reinstalar a versão estável usando **apenas** `compose.yaml`:

```bash
APP_VERSION=1.0.0 docker compose -f compose.yaml \
  --env-file config/.env.prod -p fp07-prod \
  up -d --pull always --force-recreate --wait --wait-timeout 90

bash scripts/smoke-test.sh
curl -s http://localhost:8003/api/status
```

**Resultado observado:** versão `1.0.0` recuperada e três endpoints HTTP 200. Não foi necessário reconstruir a imagem estável.

### Automático — Desafio A

O script recebe a versão pretendida e a versão estável, valida os argumentos, instala, testa e só faz rollback se `ALLOW_ROLLBACK=true`.

```bash
# Release funcional
bash scripts/deploy.sh 1.0.0 1.0.0

# Falha sem autorização de rollback
SIMULATE_DEPLOY_FAILURE=true ALLOW_ROLLBACK=false \
  bash scripts/deploy.sh 1.1.0 1.0.0

# Falha com rollback automático
SIMULATE_DEPLOY_FAILURE=true ALLOW_ROLLBACK=true \
  bash scripts/deploy.sh 1.1.0 1.0.0
```

Mesmo após recuperação bem-sucedida, o script devolve **código 1**, pois a release `1.1.0` foi rejeitada. Usa `set -Eeuo pipefail`; não armazena credenciais.

## 8. Integração Jenkins — Desafio B

Pipeline definida no `Jenkinsfile` do repositório, executada no agente `ci-python-docker`, com job `fp07-deployment` configurado como **Pipeline script from SCM**, branch `main` e caminho `Jenkinsfile`.

Parâmetros: `APP_VERSION`, `STABLE_VERSION`, `ALLOW_ROLLBACK`, `SIMULATE_DEPLOY_FAILURE`.

O ambiente Jenkins usa `config/.env.jenkins.example` copiado para `config/.env.jenkins`, projeto Compose `fp07-jenkins`, porta publicada `8004` e `BASE_URL=http://docker-engine:8004`. O agente comunica com um Docker Engine de laboratório distinto do Docker Desktop utilizado no deployment local.

| Build | Parâmetros principais | Resultado |
|---|---|---|
| `#2` | `1.0.0`, estável `1.0.0`, sem falha simulada | **SUCCESS**; 3 HTTP 200 |
| `#3` | `1.1.0`, estável `1.0.0`, falha simulada, rollback autorizado | 2 HTTP 503; rollback; 3 HTTP 200; **FAILURE** intencional |

O build inicial `#1` falhou antes do deployment por parâmetros ainda não disponibilizados na primeira execução. A segunda execução validou o fluxo. A pipeline não faz `docker login`, pois a imagem utilizada é pública. Para um registry privado, configurar Jenkins Credentials e autenticação segura sem introduzir segredos no código.

## 9. Troubleshooting adicional — Desafio C

| Cenário | Sintoma / diagnóstico | Correção e resultado |
|---|---|---|
| A — Tag inexistente | `docker pull danielabastos/app-suporte:9.9.9` devolveu `not found`; tag não publicada | `docker pull danielabastos/app-suporte:1.0.0` validado |
| B — Porta ocupada | Segundo container tentou publicar `8003`; `port is already allocated` | Utilizada porta `8005`; `/health` respondeu HTTP 200 |
| C — Healthcheck incorreto | Endpoint inexistente originou HTTP 404 e container `unhealthy`, apesar de `/health` responder 200 | Healthcheck alterado para `/health`; container `healthy` |
| D — Credenciais ausentes / sem permissões | **Não foi reproduzida uma falha de autenticação real.** O teste a repositório não criado devolveu `not found`, erro que não prova falta de permissões | Correção **proposta**: confirmar repositório/tag, autenticar com conta autorizada (`docker login`) e usar Jenkins Credentials em ambientes privados. Validou-se apenas o pull da imagem **pública** `1.0.0` |

O relatório detalhado dos incidentes e as capturas estão em `../entregaveis/README_Entrega.md` e `../entregaveis/evidencias/` na estrutura de entrega local.

## 10. Limpeza do laboratório

Após recolher as evidências, parar/remover apenas os recursos do projeto pretendido. **Não usar `-v`**.

```bash
# No Docker Desktop local
APP_VERSION=1.0.0 docker compose -f compose.yaml \
  --env-file config/.env.prod -p fp07-prod down

# No Docker Engine do agente Jenkins (se necessário e autorizado):
# executar no agente com acesso a esse daemon
APP_VERSION=1.0.0 docker compose -f compose.yaml \
  --env-file config/.env.jenkins -p fp07-jenkins down
```

A limpeza dos containers temporários de troubleshooting foi verificada: não restaram containers `fp07-port*` nem `fp07-healthcheck*`. A remoção dos deployments principais deve ser feita apenas quando já não forem necessários para testes ou demonstração.

## 11. Evidências e relatório

As capturas dos exercícios E01–E04 e dos Desafios A, B e C estão reunidas na pasta de entrega `entregaveis/evidencias/`. Consultar `entregaveis/README_Entrega.md` para índice completo e relatório sucinto de incidente. Não publicar ficheiros `.env` reais, tokens, passwords ou outros segredos.
