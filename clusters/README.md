# Clusters

Cada cluster possui sua propria arvore de bootstrap, plataforma e workloads.

Convencao:
- `clusters/<cluster>/bootstrap`: app-of-apps e entrada do Argo CD
- `clusters/<cluster>/platform`: recursos compartilhados e cluster-wide
- `clusters/<cluster>/workloads`: aplicacoes por ambiente logico