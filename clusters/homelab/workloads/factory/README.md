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
