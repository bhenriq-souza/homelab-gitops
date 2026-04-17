# Clusters

Cada cluster possui sua propria arvore de bootstrap, plataforma e workloads.

Convencao:
- `clusters/<cluster>/bootstrap`: app-of-apps e entrada do Argo CD
- `clusters/<cluster>/platform`: recursos compartilhados e cluster-wide
- `clusters/<cluster>/workloads`: aplicacoes por ambiente logico

Observacao:
- a arvore de um cluster futuro pode existir antes do bootstrap Terraform/K3s; nesse caso ela funciona apenas como scaffold e nao como cluster ativo