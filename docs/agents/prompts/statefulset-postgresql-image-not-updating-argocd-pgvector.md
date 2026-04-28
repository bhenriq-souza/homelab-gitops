# Problema: StatefulSet postgresql não atualiza imagem para pgvector/pgvector:pg16

## Contexto

O ambiente é um **homelab Kubernetes (k3s)** gerenciado via **ArgoCD** com GitOps.

- Repositório GitOps: `https://github.com/bhenriq-souza/homelab-gitops.git`
- Branch monitorada: `main`
- ArgoCD Application: `dev-workloads` (namespace `argocd`)
- Namespace alvo: `dev-apps`
- Sync policy: `automated` com `selfHeal: true` e `prune: true`

O objetivo é trocar a imagem do PostgreSQL de `postgres:16-alpine` para `pgvector/pgvector:pg16`, pois a imagem alpine **não inclui a extensão `pgvector`**, necessária para o projeto `techlead-joe-knowledge-injection-service` armazenar embeddings vetoriais.

---

## Problema observado

Apesar de o arquivo `statefulset.yaml` no repositório local já conter a imagem correta:

```yaml
image: pgvector/pgvector:pg16
```

O pod `postgresql-0` continua rodando com a imagem antiga:

```
kubectl get pod postgresql-0 -n dev-apps -o jsonpath='{.spec.containers[0].image}'
# saída: postgres:16-alpine
```

---

## Causa raiz provável

A mudança no `statefulset.yaml` **não foi commitada e pushed** para a branch `main` do repositório remoto. O ArgoCD monitora o repositório remoto — alterações apenas no clone local não são detectadas.

Adicionalmente, mesmo que o commit tenha sido feito, pode haver um dos seguintes bloqueios:

1. **ArgoCD Application está `OutOfSync` mas com sync bloqueado** — verificar status no ArgoCD UI ou CLI.
2. **StatefulSet update strategy** — o Kubernetes por padrão usa `RollingUpdate` em StatefulSets, mas se houver `updateStrategy: OnDelete`, a troca de imagem só ocorre ao deletar o pod manualmente.
3. **Erro de pull da nova imagem** — `imagePullPolicy: IfNotPresent` pode fazer o kubelet usar a imagem antiga em cache sem tentar baixar a nova se o nome da tag não mudou (não é o caso aqui, pois as tags diferem).

---

## Arquivos relevantes

```
homelab-gitops/
└── clusters/
    └── homelab/
        ├── bootstrap/
        │   └── root/
        │       └── applications/
        │           └── dev-workloads.yaml          # ArgoCD Application — sync da branch main
        └── workloads/
            └── dev/
                ├── kustomization.yaml              # inclui manifests/postgresql
                └── manifests/
                    └── postgresql/
                        ├── statefulset.yaml        # ← imagem já corrigida para pgvector/pgvector:pg16
                        ├── externalsecret.yaml     # secret postgresql-auth com credenciais
                        └── kustomization.yaml
```

**`dev-workloads.yaml` (ArgoCD Application):**
```yaml
source:
  repoURL: https://github.com/bhenriq-souza/homelab-gitops.git
  targetRevision: main
  path: clusters/homelab/workloads/dev
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

---

## O que precisa ser feito

### 1. Commitar e fazer push da mudança para o repositório remoto

```bash
cd homelab-gitops
git add clusters/homelab/workloads/dev/manifests/postgresql/statefulset.yaml
git commit -m "fix: replace postgres:16-alpine with pgvector/pgvector:pg16 for vector extension support"
git push origin main
```

### 2. Aguardar o ArgoCD detectar e sincronizar (ou forçar manualmente)

```bash
# Verificar status atual
argocd app get dev-workloads

# Forçar sync imediato (se ArgoCD CLI disponível)
argocd app sync dev-workloads

# Ou via kubectl — forçar refresh da Application
kubectl annotate application dev-workloads -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite
```

### 3. Verificar o rollout do StatefulSet

```bash
kubectl rollout status statefulset/postgresql -n dev-apps

# Confirmar imagem do pod
kubectl get pod postgresql-0 -n dev-apps -o jsonpath='{.spec.containers[0].image}'
# esperado: pgvector/pgvector:pg16
```

### 4. Verificar se o vector.so está presente

```bash
kubectl exec -it postgresql-0 -n dev-apps -- \
  find /usr -name "vector*" 2>/dev/null
```

### 5. Criar a extensão no banco

```bash
kubectl exec -it postgresql-0 -n dev-apps -- \
  psql -U "$POSTGRES_USER" -d homelab_ai -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

---

## Verificação final

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
-- esperado: vector | 0.x.x
```

---

## Observações

- A imagem `pgvector/pgvector:pg16` é um drop-in replacement de `postgres:16` (Debian slim) — **mesmas variáveis de ambiente, volumes e porta 5432**.
- Dados existentes no PVC são preservados.
- O secret `postgresql-auth` já foi corrigido anteriormente (problema de `POSTGRES_DB` divergente que impedia o readiness probe de passar).
