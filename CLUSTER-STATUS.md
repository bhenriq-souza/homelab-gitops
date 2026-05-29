# Homelab Cluster — Status Report

> Gerado em: 2026-05-13  
> Contexto: análise dos repositórios `homelab-infra`, `homelab-gitops` e `techlead-joe-*`

---

## 1. Visão Geral da Infraestrutura

### Nós e endpoints ativos

| Hostname | Papel | IP | Estado |
|---|---|---|---|
| `hlb-beelink01` | Homelab server — host K3s | `192.168.15.97` | ✅ Operacional |
| AI Lab (Ubuntu workstation) | Dev + inferência LLM (RTX 5070) | `192.168.15.103` | ✅ Operacional |
| Laptop admin (Windows 11 + WSL) | Administração principal | DHCP dinâmico | — |
| Roteador MitraStar | Gateway | `192.168.15.1` | — |

### Rede do cluster

| Recurso | CIDR |
|---|---|
| LAN | `192.168.15.0/24` |
| Pod CIDR | `10.42.0.0/16` |
| Service CIDR | `10.43.0.0/16` |

> Sem sobreposição entre LAN, cluster e GCP.

---

## 3. Stack Implantada no Cluster `homelab`

### 3.1 Plataforma (namespace `argocd`)

| Componente | Estado | Observações |
|---|---|---|
| **Argo CD** | ✅ Operacional | Bootstrap raiz `homelab-root` aponta para `homelab-gitops/clusters/homelab/bootstrap/root` |
| App-of-apps raiz | ✅ Ativo | Gerencia `shared-platform`, `dev-workloads`, `prd-workloads`, `shared-secrets-operator`, `shared-secrets-config` |

### 3.2 Observabilidade (namespace `observability`)

| Componente | Versão/Chart | Estado | Configuração |
|---|---|---|---|
| **kube-prometheus-stack** | `58.7.2` | ✅ Synced/Healthy | Prometheus retention 2d/2GB, Grafana via Traefik ingress (`grafana.homelab.local`) |
| **Loki** | `6.16.0` | ✅ Synced/Healthy | SingleBinary, retention 7d, 10Gi PVC, gateway com ingress (`loki.homelab.local`) |
| **Grafana Alloy** | chart grafana/alloy | ✅ Synced/Healthy | DaemonSet coletando logs de pods/containers |
| alertmanager | — | 🔕 Desabilitado | Fora do escopo desta fase |

**Datasource Loki** configurado no Grafana via `additionalDataSources`. Dashboards de node, namespace, pod e restart/falhas validados.

### 3.3 Secrets / Segurança (namespace `external-secrets`)

| Componente | Estado | Observações |
|---|---|---|
| **External Secrets Operator** | ✅ Operacional | Integração com GCP Secret Manager via WIF |
| `ClusterSecretStore` gcp-dev | ✅ Ativo | SA `eso-gcp-dev` com WIF |
| `ClusterSecretStore` gcp-prd | ✅ Ativo | SA `eso-gcp-prd` com WIF |
| `imagePullSecret` (dev-apps) | ✅ Gerenciado | ExternalSecret criando secret do Artifact Registry |
| `imagePullSecret` (prd-apps) | ✅ Gerenciado | ExternalSecret criando secret do Artifact Registry |

### 3.4 Ingress

| Componente | Estado | Observações |
|---|---|---|
| **Traefik** | ✅ Operacional | Configurado via `shared-traefik-config`; IngressRouteTCP para PostgreSQL |

### 3.5 Workloads — `dev-apps`

| Workload | Tipo | Estado | Observações |
|---|---|---|---|
| **PostgreSQL** (`pgvector/pgvector:pg16`) | StatefulSet | ✅ Definido no GitOps | 8Gi PVC, CPU 50m–300m, Mem 128Mi–512Mi; liveness/readiness via `pg_isready` |
| `postgresql-auth` | Secret (ESO) | ✅ Gerenciado via ExternalSecret | Credenciais do GCP Secret Manager |
| `myapp` | Deployment | ✅ Definido | App de teste para validação de pipeline |

> `prd-apps`: apenas bootstrap configmap e imagePullSecret definidos; workloads ainda não promovidos.

---

## 4. Repositório GitOps — Estado da Migração

| Item | Status |
|---|---|
| Repositório `homelab-gitops` criado e publicado no `main` | ✅ |
| Estrutura `cluster-first` (`clusters/homelab`, `clusters/ai-lab`) | ✅ |
| Conteúdo migrado de `homelab-infra/gitops` | ✅ |
| Terraform atualizado com nova `gitops_repo_url` | ⚠️ **Pendente** — terraform apply para cutover oficial |
| Verificação de sync das `Application` pós-cutover | ⚠️ **Pendente** |
| Encerramento do uso operacional de `homelab-infra/gitops` | ⚠️ **Pendente** |
| Scaffold `clusters/ai-lab` criado | ✅ (aguardando K3s) |

---

## 5. CI/CD Pipeline (Fase 7)

### GCP / Terraform

| Recurso | Estado |
|---|---|
| Artifact Registry `homelab-apps` (`us-central1`) | ✅ Provisionado |
| WIF pool + provider GitHub OIDC | ✅ Provisionado |
| SA `github-actions-ci` com `roles/artifactregistry.writer` | ✅ Configurado |
| SA `artfact-reader` para image pull secret | ✅ Configurado |
| Secrets no GCP Secret Manager (dockerconfigjson) | ✅ Configurado |

### Workflows GitHub Actions

| Item | Estado |
|---|---|
| Reusable workflow `docker-build-push.yaml` em `homelab-gitops` | ✅ Criado |
| Steps: auth GCP, docker build, push AR, update manifest, commit | ✅ Implementado |
| PAT fine-grained configurado como secret | ✅ Configurado |
| Imagem `myapp` publicada manualmente no AR e validada no cluster | ✅ |
| Caller workflow no **primeiro app repo real** (ex: `finances-control-backend`) | ❌ Pendente |
| Fluxo end-to-end via GitHub Actions (push → build → deploy) | ❌ Pendente |
| Documentação dos inputs do caller workflow | ❌ Pendente |

---

## 6. Progresso por Fase do Roadmap

| Fase | Nome | Status |
|---|---|---|
| **Fase 0** | Arquitetura | ✅ Concluída |
| **Fase 1** | Host (Ubuntu Server 24.04, hlb-beelink01) | ✅ Concluída (pendência menor: SSH hardening/UFW) |
| **Fase 2** | Rede (IP plan, LAN, plano híbrido) | ✅ Concluída |
| **Fase 3** | Cluster local (K3s single-node) | ✅ Concluída |
| **Fase 4** | Fundação IaC + GitOps (Terraform + Argo CD) | ✅ Concluída |
| **Fase 5** | Observabilidade base (kube-prometheus-stack) | ✅ Concluída |
| **Fase 6** | Logs centralizados (Loki + Grafana Alloy) | ✅ Concluída |
| **Fase 7** | CI/CD Pipeline | 🔄 ~85% — falta validação end-to-end via app repo real |
| **Fase 8** | Integração com app (PostgreSQL dev→prd) | 🔄 Em andamento — manifests dev prontos, validação e prd pendentes |
| **Fase 9** | AI Lab + fleet multi-cluster | 🔄 Em andamento — Docker Compose validado, K3s pendente |

### Pendências críticas abertas

1. **Terraform cutover** — aplicar `terraform apply` para migrar `homelab-root` para `homelab-gitops`
2. **CI/CD end-to-end** — caller workflow no repositório de app real; validar push→deploy completo
3. **PostgreSQL dev** — validar conectividade de workload, backup/restore e gates para promoção prd
4. **K3s no AI Lab** — instalar K3s + bootstrapar Argo CD no `192.168.15.103`
5. **SSH hardening** — encerrar transição desabilitando senha no SSH; aplicar baseline UFW

---

## 7. AI Lab — Estado Atual (techlead-joe-infra)

### Hardware

| Componente | Especificação |
|---|---|
| CPU | AMD Ryzen 9 7900X (12c/24t) |
| GPU | Asus RTX 5070 ATS OC — 12 GB GDDR7, Blackwell (sm_120) |
| RAM | 64 GB DDR5 5600 MHz |
| SSD dados | NVMe 2 montado em `/data` |
| OS | Ubuntu 26.04 LTS nativo |
| IP LAN | `192.168.15.103` (DHCP reservado) |

### Stack Docker Compose (`experiments/ai-lab`) — **VALIDADO em 2026-05-13**

| Serviço | Modelo | Runtime | Estado | Porta |
|---|---|---|---|---|
| **Ollama** | `qwen2.5:7b` | **GPU** (RTX 5070) | ✅ Operacional | `0.0.0.0:11434` |
| **TEI** (embeddings) | `BAAI/bge-m3` (1024d, multilingual) | **CPU** (workaround Blackwell) | ✅ Operacional | `0.0.0.0:8080` |

> **Nota TEI:** imagem `blackwell-latest` e `hopper-latest` falham (bug upstream — `libcurand.so.10` ausente e incompatibilidade de compute cap). Fallback para `cpu-latest` é viável com 64 GB DDR5 — qualidade dos vetores idêntica, latência de ~50–800 ms por chamada (aceitável para Knowledge Ingestion em batch e irrelevante para RAG).

### Critérios de aceite validados

| Critério | Status |
|---|---|
| Ollama `/v1/chat/completions` (OpenAI-compat) | ✅ |
| TEI `/embed` e `/v1/embeddings` retornam vetor | ✅ |
| Container Ollama com runtime NVIDIA | ✅ |
| Container TEI em CPU (workaround Blackwell) | ✅ |
| Bind mounts em `/data` persistem após `down/up` | ✅ |
| Docker data-root em `/data/docker` | ✅ |

### Itens em aberto (AI Lab)

| Item | Prioridade | Estado |
|---|---|---|
| Reserva DHCP formal no roteador para `192.168.15.103` | P0 | Em uso, reserva não formalizada |
| TEI em GPU — aguardando suporte Blackwell upstream | P1 | Aberto |
| GPU enablement Fase 2 (NVIDIA Device Plugin no K3s) | P1 | Aberto |
| ArgoCD bootstrap para Cluster A (ai-lab K3s) | P1 | Aberto |
| Backup SSD `/data` (crítico: volumes Docker Postgres/Qdrant) | P1 | Aberto |

---

## 8. Projeto techlead-joe — Visão Geral e Progresso

O projeto **Tech Lead Joe** é uma plataforma de análise automatizada de incidentes que:
- Recebe sinais de observabilidade do Kubernetes
- Enriquece com base de conhecimento técnico via RAG
- Usa LLM local (Ollama) para redigir análise padronizada
- Abre tickets no Jira e notifica o Slack automaticamente

### Arquitetura macro

```
Git docs ──► knowledge-injector ──► TEI embeddings ──► PostgreSQL/pgvector ──► RAG
Observabilidade ──► RabbitMQ ──► Incident Analyzer ──► LLM (Ollama) ──► Jira/Slack
```

**Cluster A (AI Lab, `192.168.15.103`):** Ollama + TEI — inferência LLM  
**Cluster B (homelab, `192.168.15.97`):** Incident Analyzer + Knowledge Injector + PostgreSQL + RabbitMQ

### 8.1 `techlead-joe-infra`

| Artefato | Estado |
|---|---|
| Discovery report (visão geral, stack, fluxos) | ✅ Concluído |
| Decisões arquiteturais (DAs documentadas) | ✅ Documentadas |
| Roadmap OpenSpec (14 specs identificadas) | ✅ Definido |
| Topologia MVP — 2 clusters definida | ✅ Fechada |
| Experimento WSL (laptop admin) | ✅ Validado (modelo menor, binds locais) |
| **Experimento AI Lab (workstation Ubuntu)** | ✅ **VALIDADO 2026-05-13** |
| K3s no AI Lab | ❌ Pendente (Fase 2) |

### 8.2 `techlead-joe-knowledge-injection-service`

Serviço Python responsável por clonar repositórios Git, detectar mudanças, chunkar documentos, gerar embeddings (TEI) e persistir no PostgreSQL/pgvector.

| Fase | Descrição | Estado |
|---|---|---|
| **1** | Bootstrap: uv, DI (dependency-injector), CLI skeleton | ✅ Concluída |
| **2** | Git source + file discovery + DB repositories | ✅ Concluída (branch `feat/database-and-repositories` mergeada) |
| **3** | PostgreSQL + Alembic migrations (schema `knowledge`, 4 tabelas, índice HNSW `vector(384)`) | ✅ Schema aplicado |
| **4** | Chunking service (MVP por tamanho fixo) | 🔜 Próxima |
| **5** | TEI embeddings client (httpx, batch 32) | 🔜 |
| **6** | `IngestionService` — orquestração end-to-end + idempotência | 🔜 |
| **7** | Kubernetes CronJob manifests | 🔜 |

**Ambientes validados para o serviço:**
- PostgreSQL: `192.168.15.97:5432`, DB `homelab_ai`, role `appuser`, pgvector 0.8.2
- TEI: `http://192.168.15.103:8080`, modelo `BAAI/bge-small-en-v1.5` (384d) — *dev/testes*

**Plano de implementação detalhado** disponível em `docs/implementation-plan.md`:  
8 passos definidos (Database engine → Repositories → GitClient → Chunking → TeiClient → IngestionService → DI wiring → smoke test end-to-end).

### 8.3 Itens em aberto do projeto (decisões P0)

| Item | Status |
|---|---|
| RabbitMQ — onde rodar e topologia de filas | 🔴 Aberto |
| Modelo LLM definitivo (tamanho, latência alvo, fallback) | 🔴 Aberto |
| Política de automação Jira (quando abrir automaticamente) | 🔴 Aberto |
| Retrieval MVP — textual puro vs híbrido | 🟡 Aberto |
| Estratégia de embeddings — consolidar no Ollama vs aguardar TEI GPU | 🟡 Aberto |
| Autenticação inter-cluster (token, mTLS ou rede privada) | 🟡 Aberto |

---

## 9. Dependências Críticas Entre Camadas

```
homelab K3s (operacional)
  └─► Argo CD reconcilia homelab-gitops
        └─► PostgreSQL dev-apps (pgvector) ◄── knowledge-injector precisa desta instância
        └─► External Secrets Operator ──────── imagePullSecrets + auth secrets
        └─► Observabilidade (Prometheus+Grafana+Loki)

AI Lab Docker Compose (operacional)
  └─► Ollama qwen2.5:7b (GPU) ◄────────────── Incident Analyzer vai consumir
  └─► TEI bge-m3 (CPU fallback) ◄────────────── knowledge-injector gera embeddings

homelab-gitops (fonte de verdade)
  └─► Terraform cutover pendente (homelab-root)
  └─► clusters/ai-lab (scaffold pronto, K3s não instalado)
```

---

## 10. Próximos Passos Recomendados

| Prioridade | Ação | Repositório |
|---|---|---|
| P0 | Aplicar terraform cutover (`homelab-root` → `homelab-gitops`) | `homelab-infra` |
| P0 | Implementar Passos 3–8 do `knowledge-injector` (chunking → smoke test) | `techlead-joe-knowledge-injection-service` |
| P0 | Fechar decisões abertas: RabbitMQ, modelo LLM, política Jira | `techlead-joe-infra` |
| P1 | Instalar K3s no AI Lab + bootstrapar Argo CD (`clusters/ai-lab`) | `homelab-infra` / `homelab-gitops` |
| P1 | Criar caller workflow no repositório de app real + validar CI/CD end-to-end | app repo + `homelab-gitops` |
| P1 | Validar PostgreSQL dev (conectividade, backup/restore) e promover para prd | `homelab-gitops` |
| P2 | Formalizar reserva DHCP do AI Lab no roteador | operacional |
| P2 | Aplicar baseline de segurança SSH + UFW no hlb-beelink01 | `homelab-infra` |
