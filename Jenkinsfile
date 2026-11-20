
pipeline {
    agent { label 'ci-python-docker' }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        string(
            name: 'APP_VERSION',
            defaultValue: '1.0.0',
            description: 'Versao a instalar'
        )
        string(
            name: 'STABLE_VERSION',
            defaultValue: '1.0.0',
            description: 'Versao estavel para rollback'
        )
        booleanParam(
            name: 'ALLOW_ROLLBACK',
            defaultValue: true,
            description: 'Autorizar rollback automatico'
        )
        booleanParam(
            name: 'SIMULATE_DEPLOY_FAILURE',
            defaultValue: false,
            description: 'Simular falha da nova release'
        )
    }

    environment {
        ENV_FILE = 'config/.env.jenkins'
        PROJECT_NAME = 'fp07-jenkins'
        BASE_URL = 'http://docker-engine:8004'
        ALLOW_ROLLBACK = "${params.ALLOW_ROLLBACK}"
        SIMULATE_DEPLOY_FAILURE = "${params.SIMULATE_DEPLOY_FAILURE}"
    }

    stages {
        stage('Validar parametros') {
            steps {
                sh '''
                    set -eu

                    case "$APP_VERSION" in
                        *[!0-9.]*|'')
                            echo "[ERRO] Versao invalida"
                            exit 2
                            ;;
                    esac

                    echo "[INFO] Nova versao: $APP_VERSION"
                    echo "[INFO] Versao estavel: $STABLE_VERSION"
                '''
            }
        }

        stage('Preparar ambiente') {
            steps {
                sh '''
                    set -eu

                    cp config/.env.jenkins.example "$ENV_FILE"

                    docker info >/dev/null
                    docker compose version

                    APP_VERSION="$APP_VERSION" docker compose \
                        -f compose.yaml \
                        --env-file "$ENV_FILE" \
                        -p "$PROJECT_NAME" \
                        config --quiet

                    echo "[OK] Ambiente validado"
                '''
            }
        }

        stage('Deployment e validacao') {
            steps {
                sh '''
                    set -eu

                    export ALLOW_ROLLBACK
                    export SIMULATE_DEPLOY_FAILURE

                    bash scripts/deploy.sh \
                        "$APP_VERSION" \
                        "$STABLE_VERSION"
                '''
            }
        }
    }

    post {
        always {
            echo 'Pipeline FP07 terminada.'
        }
        success {
            echo '[SUCESSO] Nova release aprovada.'
        }
        failure {
            echo '[FALHA] Deployment nao aprovado. Consultar logs para verificar rollback.'
        }
    }
}
