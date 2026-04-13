# Migration Guide

## Objetivo
Concluir a troca da fonte GitOps do cluster atual do repositório anterior para este repositório dedicado, mantendo a mesma topologia funcional de `Application` no Argo CD.

## Escopo desta etapa
- cluster atual: `homelab`
- origem anterior: `homelab-infra/gitops`
- nova origem: `homelab-gitops/clusters/homelab`

## O que ja foi migrado
- `bootstrap/root`
- `platform`
- `external-secrets`
- `workloads/dev`
- `workloads/prd`

## Premissas
- este repositório ja foi enviado ao remoto `main`
- o Argo CD atual continua saudavel
- o cluster atual ainda opera com os mesmos namespaces e destinos Kubernetes
- o bootstrap raiz `homelab-root` continua gerenciado por Terraform no repositorio `homelab-infra`

## Estrategia adotada
Os nomes atuais das `Application` foram preservados.

Beneficio:
- o cutover atualiza as `Application` existentes, em vez de criar uma segunda arvore paralela com nomes diferentes

## Passos recomendados de cutover

### 1. Publicar o repositório novo
Garantir que o branch com a migracao esteja no remoto esperado.

### 2. Validar renderizacao final
Executar localmente:

```bash
kubectl kustomize clusters/homelab/bootstrap/root
kubectl kustomize clusters/homelab/platform
kubectl kustomize clusters/homelab/workloads/dev
kubectl kustomize clusters/homelab/workloads/prd
```

### 3. Atualizar o bootstrap Terraform
No repositorio `homelab-infra`, garantir os valores abaixo no ambiente `shared`:

```hcl
gitops_repo_url  = "https://github.com/bhenriq-souza/homelab-gitops.git"
gitops_root_path = "clusters/homelab/bootstrap/root"
gitops_target_revision = "main"
```

### 4. Reaplicar o ambiente `shared`
Executar o apply do bootstrap Terraform para atualizar o `homelab-root`:

```bash
terraform -chdir=terraform/environments/shared init
terraform -chdir=terraform/environments/shared plan
terraform -chdir=terraform/environments/shared apply
```

Efeito esperado:
- `homelab-root` passa a apontar para `clusters/homelab/bootstrap/root`
- `shared-platform` passa a apontar para `clusters/homelab/platform`
- `shared-secrets-config` passa a apontar para `clusters/homelab/platform/external-secrets`
- `dev-workloads` passa a apontar para `clusters/homelab/workloads/dev`
- `prd-workloads` passa a apontar para `clusters/homelab/workloads/prd`

### 5. Verificar sincronizacao no Argo CD
Validar:

```bash
kubectl -n argocd get applications.argoproj.io
kubectl -n argocd get applications.argoproj.io homelab-root -o yaml | grep -E "repoURL|path"
kubectl -n argocd get applications.argoproj.io shared-platform -o yaml | grep -E "repoURL|path"
kubectl -n argocd get applications.argoproj.io shared-secrets-config -o yaml | grep -E "repoURL|path"
kubectl -n argocd get applications.argoproj.io dev-workloads -o yaml | grep -E "repoURL|path"
kubectl -n argocd get applications.argoproj.io prd-workloads -o yaml | grep -E "repoURL|path"
```

### 6. Validar saude dos componentes principais
Conferir:

```bash
kubectl -n argocd get pods
kubectl -n observability get pods
kubectl -n external-secrets get pods
kubectl -n dev-apps get pods
kubectl -n prd-apps get pods
```

### 7. Encerrar a estrutura antiga
Depois do cluster estar estavel:
- remover o uso operacional de `homelab-infra/gitops`
- manter o repositório antigo apenas como referencia historica ate a limpeza planejada

## Riscos principais
- aplicar o cutover antes de publicar o repositório novo no `main`
- atualizar as `Application` filhas sem atualizar tambem o `homelab-root`
- trocar nomes de `Application` durante o primeiro corte e criar arvore duplicada
- misturar mudanca estrutural com refactor de manifests no mesmo ciclo

## Proxima etapa apos o cutover
- criar `clusters/<novo-cluster>`
- bootstrapar um novo Argo CD apontando para este mesmo repositório
- extrair componentes realmente compartilhados para `components/`