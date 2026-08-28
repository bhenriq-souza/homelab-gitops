# Conectando uma aplicação nova ao pipeline

Passos para um repositório de aplicação passar a publicar imagens no Artifact Registry e ter o deploy reconciliado pelo Argo CD.

Ao longo do texto, `<app>` é o **app-name** — que também é o nome do diretório do manifesto. Frontend e backend são apps distintas: o workflow assume **um app-name = um `deployment.yaml` = uma imagem**.

## 1. Autorizar o repositório no GCP (Workload Identity Federation)

No repositório [`homelab-infra`](https://github.com/bhenriq-souza/homelab-infra), acrescente o repositório em `github_allowed_repositories` no arquivo `terraform/clusters/homelab/bootstrap/terraform.tfvars` e aplique o Terraform.

> ⚠️ Hoje esse root tem drift: um `apply` sem `-target` planeja destruições em recursos de CI existentes. Aplique com `-target` no provider WIF e nos bindings IAM até o drift ser resolvido.

## 2. Criar a deploy key de escrita neste repositório

O CI da aplicação precisa escrever aqui para atualizar a tag da imagem. Use uma **deploy key por aplicação** — assim cada uma é revogável isoladamente, sem afetar as outras.

Não use PAT: um PAT é credencial de conta pessoal, com alcance maior que o necessário, e **expira** — o pipeline quebraria numa data futura sem aviso. A deploy key pertence ao repositório, não a uma pessoa, e não expira.

```bash
APP_REPO=bhenriq-souza/<app-repo>
KEY=$(mktemp -u)

ssh-keygen -t ed25519 -N '' -C "<app-repo> CI → homelab-gitops" -f "$KEY"

# Cadastra a pública aqui, COM escrita
gh api -X POST repos/bhenriq-souza/homelab-gitops/keys \
  -f title="<app-repo> CI (image tag bumps)" \
  -f key="$(cat $KEY.pub)" \
  -F read_only=false

# Grava a privada como secret no repositório da aplicação
gh secret set GITOPS_DEPLOY_KEY -R "$APP_REPO" < "$KEY"

shred -u "$KEY" && rm -f "$KEY.pub"   # não deixe a chave privada em disco
```

## 3. Configurar os secrets no repositório da aplicação

| Secret | Valor |
|---|---|
| `GCP_WIF_PROVIDER` | `projects/702302784311/locations/global/workloadIdentityPools/github-actions-pool/providers/github-actions-provider` |
| `GCP_SERVICE_ACCOUNT` | `github-actions-ci@homelab-492918.iam.gserviceaccount.com` |
| `GITOPS_DEPLOY_KEY` | chave privada gerada no passo 2 |

Os dois primeiros saem dos outputs do Terraform e não são sensíveis — são identificadores.

## 4. Criar os manifestos aqui

Copie a estrutura de um workload existente para `clusters/homelab/workloads/dev/manifests/<app>/` e registre o diretório em `clusters/homelab/workloads/dev/kustomization.yaml`. A `Application` `dev-workloads` já sincroniza automaticamente — não é preciso criar uma nova.

Pontos que costumam ser esquecidos:

- **Acesso ao PostgreSQL:** o pod precisa da label `homelab.io/database-access: postgresql` em `spec.template.metadata.labels`, senão a NetworkPolicy bloqueia a porta 5432.
- **Ingress:** use `ingressClassName: traefik`, não a annotation `kubernetes.io/ingress.class`, que está depreciada.
- **Imagem:** o `deployment.yaml` precisa de `imagePullSecrets: [ar-image-pull-secret]` e a linha da imagem no formato `image: <registry>/<app>:<tag>` — é ela que o pipeline reescreve com `sed`.
- **Recursos:** o cluster é single-node; siga o padrão conservador (~50m CPU / 128Mi de request).

## 5. Chamar o workflow reutilizável no repositório da aplicação

```yaml
jobs:
    deploy:
        uses: bhenriq-souza/homelab-gitops/.github/workflows/docker-build-push.yaml@main
        with:
            app-name: <app>
            environment: dev
        secrets:
            GCP_WIF_PROVIDER: ${{ secrets.GCP_WIF_PROVIDER }}
            GCP_SERVICE_ACCOUNT: ${{ secrets.GCP_SERVICE_ACCOUNT }}
            GITOPS_DEPLOY_KEY: ${{ secrets.GITOPS_DEPLOY_KEY }}
```

## 6. DNS

Aponte `<app>.dev.homelab.local` para o IP do Traefik (`192.168.15.97`) no seu resolvedor local ou no roteador.
