#!/usr/bin/env bash
#
# Cria database e role dedicados para uma aplicação no PostgreSQL do cluster.
#
# Idempotente: rodar de novo não altera nada além de reafirmar a senha do role.
# A senha nunca é gerada nem gravada aqui — ela vem do ambiente e o seu destino é
# o GCP Secret Manager, de onde o External Secrets Operator a entrega ao pod.
#
# Uso:
#   APP_PASSWORD='...' ./scripts/provision-app-database.sh finances_dev finances_app
#
set -euo pipefail

APP_DB="${1:?uso: provision-app-database.sh <database> <role>}"
APP_ROLE="${2:?uso: provision-app-database.sh <database> <role>}"
NAMESPACE="${NAMESPACE:-dev-apps}"
POSTGRES_POD="${POSTGRES_POD:-postgresql-0}"
ADMIN_USER="${ADMIN_USER:-appuser}"
ADMIN_DB="${ADMIN_DB:-homelab_ai}"

: "${APP_PASSWORD:?exporte APP_PASSWORD com a senha do role}"

# Aspa simples dobrada: a senha entra no SQL como literal, e o `format(%L)`
# adiante a requota para o comando final.
ESCAPED_PASSWORD="${APP_PASSWORD//\'/\'\'}"

psql_admin() {
    kubectl exec -i -n "${NAMESPACE}" "${POSTGRES_POD}" -- \
        psql -v ON_ERROR_STOP=1 -U "${ADMIN_USER}" -d "${1}" -q
}

echo "==> role ${APP_ROLE}"
psql_admin "${ADMIN_DB}" <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${APP_ROLE}') THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', '${APP_ROLE}', '${ESCAPED_PASSWORD}');
    ELSE
        EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', '${APP_ROLE}', '${ESCAPED_PASSWORD}');
    END IF;
END
\$\$;
SQL

echo "==> database ${APP_DB}"
# CREATE DATABASE não roda dentro de bloco transacional, então o gate é o \gexec.
psql_admin "${ADMIN_DB}" <<SQL
SELECT format('CREATE DATABASE %I OWNER %I', '${APP_DB}', '${APP_ROLE}')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${APP_DB}')
\gexec
SQL

echo "==> propriedade do schema public em ${APP_DB}"
# No PostgreSQL 15+ o schema public não aceita mais CREATE de qualquer role: sem
# esta linha, a primeira migration falha por permissão.
psql_admin "${APP_DB}" <<SQL
ALTER DATABASE ${APP_DB} OWNER TO ${APP_ROLE};
ALTER SCHEMA public OWNER TO ${APP_ROLE};
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT ALL ON SCHEMA public TO ${APP_ROLE};
SQL

echo
echo "Pronto. A URL a gravar no Secret Manager tem a forma:"
echo "  postgres://${APP_ROLE}:<senha>@postgresql.${NAMESPACE}.svc.cluster.local:5432/${APP_DB}"
