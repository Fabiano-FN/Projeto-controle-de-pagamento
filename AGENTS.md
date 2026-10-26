# Regras de Trabalho do Projeto — Controle de Pagamentos da Atlética

## 1. Aprovação Prévia de Decisões (Não decidir sozinho)
- Nunca tome decisões de negócio, arquitetura ou modelagem por conta própria quando encontrar um caso não previsto em `docs/ESPECIFICACOES.md`.
- Sempre apresente sugestões claras (com opções, vantagens, desvantagens e trade-offs) e aguarde a aprovação explícita do usuário antes de implementar ou alterar a especificação.

## 2. Rastreamento de Progresso em `docs/FUNCIONALIDADES.md`
- Toda vez que finalizarmos a revisão de uma funcionalidade/etapa e partirmos para a próxima etapa, marque obrigatoriamente `[x]` no checkbox correspondente dentro do arquivo `docs/FUNCIONALIDADES.md`.
- Mantenha `docs/ESPECIFICACOES.md`, `docs/FUNCIONALIDADES.md` e o código/SQL sempre sincronizados.

## 3. Controle de Branches e Push no GitHub por Etapa
- Sempre que finalizar uma funcionalidade/etapa de `docs/FUNCIONALIDADES.md`, sinalize explicitamente ao usuário que a etapa está pronta para ser subida na sua respectiva branch no GitHub (`feat/...` e merge em `dev`/`main` quando aplicável), fornecendo a mensagem de commit recomendada e realizando/orientando o `git push` antes de iniciar a próxima funcionalidade.

