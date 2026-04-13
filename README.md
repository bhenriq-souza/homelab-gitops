# homelab-gitops

Repositório dedicado ao estado desejado dos clusters do homelab reconciliados pelo Argo CD.

## Estrutura
- `clusters/`: ponto de entrada por cluster
- `components/`: componentes reutilizáveis entre clusters

## Modelo adotado
- `cluster-first`
- um `bootstrap/root` por cluster
- separação entre `platform` e `workloads`

## Cluster atual
O primeiro cluster migrado para esta estrutura é:
- `clusters/homelab`

## Migração inicial
Nesta primeira etapa, o conteúdo funcional do cluster atual foi portado da estrutura anterior para o repositório dedicado sem reescrever manifests desnecessariamente.

Objetivo:
- preservar compatibilidade operacional
- trocar a fonte GitOps para o repositório dedicado
- preparar a evolução para novos clusters