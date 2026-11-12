# factory

Banco operacional da [ftech-software-factory](https://github.com/bhenriq-souza/ftech-software-factory):
tenants, work items espelhados, runs, turns e custos. Fica num namespace próprio, separado do
PostgreSQL de `dev-apps` e `prd-apps`, porque guarda metadados de clientes (títulos e descrições de
work items) e tem outro ciclo de vida.

| Item | Valor |
|---|---|
| Namespace | `factory` (Application `factory` no Argo CD) |
| Database / role | `factory` / `factory` |
| No cluster | `postgresql.factory.svc.cluster.local:5432` |
| Na LAN | `192.168.15.97:5433` (entrypoint `factorypg` do Traefik, restrito a `192.168.15.0/24`) |
| Senha | GCP Secret Manager `factory-postgres-password` (projeto `homelab-492918`), via `ClusterSecretStore` `gcp-sm-factory` |

## Antes do primeiro sync

O secret precisa existir no Secret Manager; sem ele o `ExternalSecret` fica em erro e o
PostgreSQL não sobe.

```bash
openssl rand -base64 30 | tr -d '/+=' | head -c 32 \
  | gcloud secrets create factory-postgres-password --data-file=- --project homelab-492918
```

## Backup

O CronJob `postgresql-backup` roda todo dia às 03:30 (horário de Brasília) e grava um `pg_dump -Fc`
no PVC `postgresql-backups`, com retenção de 7 dias.

> ⚠️ O PVC está no mesmo disco do nó (`local-path`). Ele protege contra erro lógico (DROP,
> migration ruim), não contra perda do disco. Uma cópia externa (bucket no GCS) é o próximo passo e
> depende de bucket e service account no `homelab-infra`.

Restaurar o dump mais recente:

```bash
kubectl -n factory exec -it postgresql-0 -- sh -c \
  'pg_restore -U factory -d factory --clean --if-exists "$(ls -t /backups/*.dump | head -1)"'
```

Isso exige montar o PVC de backup no pod, ou copiar o arquivo antes com `kubectl cp` a partir de
um pod do job.

## Orquestrador (`ft-coders-orchestrator`)

O control plane da FT Coders roda aqui (spec 0022 do `ft-coders`). O runner continua na ai-lab, como serviço do usuário. São 1 réplica com `Recreate`, um init container `factory db migrate` e o container `factory orchestrator`.

| Item | Valor |
|---|---|
| Imagem | `homelab-apps/ft-coders-orchestrator:sha-<commit>`, publicada pelo `deploy.yml` do `ft-coders` a cada merge no `main` |
| Segredos | chave da SA `ft-coders-orchestrator` (`factory-orchestrator-sa-key`), que lê os segredos do tenant no Secret Manager sob demanda; senha do banco por `PGPASSWORD`, do `postgresql-auth` |
| Saída de rede | DNS, Postgres do namespace e TCP 443 fora das faixas privadas (`networkpolicy.yaml`) |
| Saúde | liveness por `factory health --max-age 900` (heartbeat a cada ciclo) |
| Logs | Loki: `{app="ft-coders", process="orchestrator"}`; dashboard "FT Coders" no Grafana |

**Antes do primeiro sync:** a SA e os bindings saem do `homelab-infra` (`ft-coders.tf`). A chave vai para o Secret Manager sem passar por arquivo:

```bash
gcloud iam service-accounts keys create /dev/stdout \
  --iam-account=ft-coders-orchestrator@homelab-492918.iam.gserviceaccount.com --project=homelab-492918 \
  | gcloud secrets create factory-orchestrator-sa-key --data-file=- --project=homelab-492918
```

**Go-live:** o manifest entra com `replicas: 0`. Depois da primeira imagem publicada, um PR troca para `replicas: 1`. Antes disso, confira que nenhum `factory orchestrator` manual está rodando. Se estiver, o pod fica em standby até ele sair.

## Grafana (dashboard "FT Coders" e datasource do Postgres)

O dashboard `ft-coders` (ConfigMap `ft-coders-dashboard`) usa dois datasources: o Loki existente e o **`FT Coders Postgres`** (uid `ft-coders-pg`, login `grafana_reader`, só `SELECT`). O datasource vem do Secret `grafana-datasource-ft-coders-pg`, gerado pelo `ExternalSecret` de mesmo nome (`manifests/postgresql/grafana-datasource-externalsecret.yaml`) a partir de `factory-grafana-reader-password`. O Secret fica no namespace `factory` porque o `ClusterSecretStore` `gcp-sm-factory` só atende esse namespace; o sidecar de datasources do Grafana o lê de lá (`searchNamespace: observability,factory` em `shared-observability`). A `NetworkPolicy` do PostgreSQL libera a porta 5432 para os pods `app.kubernetes.io/name=grafana` do namespace `observability`.

**O que o Bruno faz, nesta ordem** (a role `ft_coders_read` já existe pela migration `0010`, aplicada pelo init container do orquestrador; não há migration nova). Mesmo padrão do `ft_coders_api` no runbook do `ft-coders`:

```bash
# 1. senha gerada direto para o Secret Manager (nunca aparece no terminal)
openssl rand -base64 48 | tr -d '/+=\n' | head -c 40 \
  | gcloud secrets create factory-grafana-reader-password --project=homelab-492918 \
      --replication-policy=automatic --data-file=-

# 2. login com essa senha, herdando só a role de leitura
export KUBECONFIG=~/.kube/config-homelab.yaml
gcloud secrets versions access latest --secret=factory-grafana-reader-password --project=homelab-492918 \
  | kubectl -n factory exec -i postgresql-0 -- sh -c '
      read -r PW
      printf "%s\n" "create role grafana_reader login password :'\''pw'\'' in role ft_coders_read;" \
        | psql -v ON_ERROR_STOP=1 -v pw="$PW" -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

# 3. conferência: membro só de ft_coders_read e sem superusuário
kubectl -n factory exec postgresql-0 -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "
  select r.rolname, r.rolsuper, array_agg(m.rolname) from pg_roles r
  join pg_auth_members a on a.member = r.oid join pg_roles m on m.oid = a.roleid
  where r.rolname = '\''grafana_reader'\'' group by 1, 2"'
```

Depois do merge, o Argo CD sincroniza `shared-observability` (sidecar) e `factory` (ExternalSecret, NetworkPolicy, dashboard). Se o `ExternalSecret` ficar em `SecretSyncedError`, o segredo do passo 1 não existe ou a SA do store não o enxerga: a liberação é no `homelab-infra` e depende de aprovação.

**Rotação:** `gcloud secrets versions add factory-grafana-reader-password --data-file=-` com senha nova, o mesmo passo 2 trocando `create role grafana_reader login password` por `alter role grafana_reader password`, e depois o ExternalSecret sincroniza (até 1 h) e o sidecar recarrega o datasource.

**Como validar**
1. `kubectl -n factory get externalsecret grafana-datasource-ft-coders-pg` em `SecretSynced`, e `kubectl -n factory get secret grafana-datasource-ft-coders-pg -o jsonpath='{.metadata.labels}'` com `grafana_datasource`.
2. No Grafana, Connections > Data sources > `FT Coders Postgres` > *Save & test* deve dar "Database Connection OK". Se falhar com timeout, é a NetworkPolicy; se for "password authentication failed", o passo 2 acima.
3. Abrir o dashboard **FT Coders**: os filtros `tenant`, `stage` e `run` devem listar valores, e a linha "Visão geral" deve ter dados no período.

O dashboard é agregado e de operação; a visão por run completa fica na UI própria. Custo (`run.cost_usd`) é nocional quando `cost_basis` é `subscription_notional`.
