# Problema: pgvector extension não disponível no PostgreSQL do homelab (k3s)

## Contexto

O ambiente é um **homelab Kubernetes (k3s)** rodando no WSL2 Ubuntu 24.04 (Windows 11 Pro).

O PostgreSQL está implantado como `StatefulSet` no namespace `dev-apps`, gerenciado via **GitOps com Flux** a partir do repositório `homelab-gitops`.

O projeto `techlead-joe-knowledge-injection-service` precisa da extensão `pgvector` no PostgreSQL para armazenar embeddings vetoriais (`vector(384)`) gerados pelo **TEI (Text Embeddings Inference)** com o modelo `BAAI/bge-small-en-v1.5`.

---

## Problema observado

Ao tentar criar a extensão `vector` no banco `homelab_ai`, o seguinte erro ocorre:

```
homelab_ai=# CREATE EXTENSION IF NOT EXISTS vector;
ERROR:  extension "vector" is not available
DETAIL:  Could not open extension control file "/usr/local/share/postgresql/extension/vector.control": No such file or directory.
HINT:  The extension must first be installed on the system where PostgreSQL is running.
```

---

## Causa raiz

A imagem Docker em uso no pod `postgresql-0` é **`postgres:16-alpine`**, que **não inclui o pgvector**.

Evidência observada no `kubectl describe pod postgresql-0 -n dev-apps`:

```
Image: postgres:16-alpine
Ready: True
```

A tentativa de trocar para `pgvector/pgvector:pg16` (imagem que inclui o pgvector pré-compilado) foi feita no manifesto do StatefulSet em:

```
clusters/homelab/workloads/dev/manifests/postgresql/statefulset.yaml
```

Porém o pod ainda está rodando com a imagem antiga. O rollout anterior (`pgvector/pgvector:pg16`) ficou com `Ready: False` por um problema no secret `postgresql-auth`, e aparentemente o StatefulSet reverteu ou o pod foi recriado com a imagem anterior.

---

## Estado atual dos arquivos no repositório

**`clusters/homelab/workloads/dev/manifests/postgresql/statefulset.yaml`** — já com a imagem correta:

```yaml
image: pgvector/pgvector:pg16
```

**`clusters/homelab/workloads/dev/manifests/postgresql/externalsecret.yaml`** — continha `POSTGRES_DB: appdb` divergindo do banco real (`homelab_ai`), o que causou falha no readiness probe e impediu o pod de ficar `Ready: True` com a nova imagem.

---

## O que precisa ser resolvido

1. **Confirmar que o secret `postgresql-auth` está correto** com as variáveis:
   - `POSTGRES_DB` — deve bater com o banco que a aplicação usa
   - `POSTGRES_USER`
   - `POSTGRES_PASSWORD`

2. **Garantir que o pod rode com `pgvector/pgvector:pg16`** e fique `Ready: True`.

3. **Após o pod subir com a imagem correta**, executar:

```sql
\c homelab_ai
CREATE EXTENSION IF NOT EXISTS vector;
```

4. **Verificar** que a extensão foi instalada:

```sql
SELECT * FROM pg_extension WHERE extname = 'vector';
```

---

## Comandos úteis para diagnóstico

```bash
# Ver qual imagem está rodando atualmente
kubectl get pod postgresql-0 -n dev-apps -o jsonpath='{.spec.containers[0].image}'

# Verificar se o arquivo vector.so existe no container
kubectl exec -it postgresql-0 -n dev-apps -- \
  find /usr -name "vector*" 2>/dev/null

# Forçar novo rollout após corrigir o secret
kubectl rollout restart statefulset/postgresql -n dev-apps
kubectl rollout status statefulset/postgresql -n dev-apps

# Testar a extensão diretamente no pod
kubectl exec -it postgresql-0 -n dev-apps -- \
  psql -U "$POSTGRES_USER" -d homelab_ai -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

---

## Arquivos relevantes no repositório

```
homelab-gitops/
└── clusters/
    └── homelab/
        └── workloads/
            └── dev/
                └── manifests/
                    └── postgresql/
                        ├── statefulset.yaml       # imagem já atualizada para pgvector/pgvector:pg16
                        ├── externalsecret.yaml    # secret com credenciais do Postgres
                        ├── kustomization.yaml
                        ├── service.yaml
                        └── networkpolicy.yaml
```

---

## Referências

- Imagem pgvector: https://hub.docker.com/r/pgvector/pgvector
- pgvector GitHub: https://github.com/pgvector/pgvector
- TEI (Text Embeddings Inference): https://github.com/huggingface/text-embeddings-inference
