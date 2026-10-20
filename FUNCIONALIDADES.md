# Mapa de Funcionalidades e Backlog — Controle de Pagamentos da Atlética

> **Como usar este arquivo:** Este documento organiza todas as funcionalidades do projeto em fases lógicas de construção. Ao trabalhar com o **Claude Sonnet / Opus**, peça para ele implementar **uma fase (ou um item) por vez** e vá marcando os checkboxes (`[x]`) conforme testar e aprovar cada entrega.

---

## Legenda de Status
* `[x]` **Definido / Especificado** (Regra de negócio pronta em [ESPECIFICACOES.md](file:///c:/Users/ff_fn/dev/Code/Projetos%20VsCode/Projeto%20controle%20de%20pagamento/ESPECIFICACOES.md))
* `[ ]` **A Construir (Pendente de Código)**

---

## Fase 0: Concepção e Arquitetura (Concluída)
- [x] Definição do escopo e regras de negócio do projeto ([Ideia.txt](file:///c:/Users/ff_fn/dev/Code/Projetos%20VsCode/Projeto%20controle%20de%20pagamento/Ideia.txt))
- [x] Escolha da Arquitetura (Web Serverless + BaaS)
- [x] Escolha da Stack (Next.js + TypeScript + Tailwind CSS + Supabase)
- [x] Especificação técnica e modelo conceitual de dados ([ESPECIFICACOES.md](file:///c:/Users/ff_fn/dev/Code/Projetos%20VsCode/Projeto%20controle%20de%20pagamento/ESPECIFICACOES.md))

---

## Fase 1: Banco de Dados, Segurança e Autenticação (Fundação)
*O primeiro passo prático com o Claude. Sem tela ainda, apenas estrutura no Supabase.*

- [x] **1.1. Criação das Tabelas SQL no Supabase (`supabase/schema.sql`):**
  - Script SQL para criar `perfis`, `parcelas`, `pagamentos`, `alocacoes_pagamento`, `logs_auditoria` e `configuracoes_atletica`.
- [x] **1.2. Políticas de Segurança (Row Level Security - RLS em `supabase/schema.sql`):**
  - Garantir no banco que `aluno` só lê/insere dados vinculados ao próprio `id`.
  - Garantir que apenas `admin` (Tesoureiro) pode ver todos os alunos, criar parcelas e aprovar pagamentos.
- [x] **1.3. Configuração do Bucket no Supabase Storage (`supabase/schema.sql`):**
  - Criar bucket privado `comprovantes` com regras de acesso por perfil.
- [ ] **1.4. Fluxo de Login e Primeiro Acesso:**
  - Tela de Login (E-mail e Senha).
  - Middleware de redirecionamento obrigatório para a tela **"Alterar Senha Provisória"** quando `precisa_trocar_senha == true`.

---

## Fase 2: Módulo do Tesoureiro — Cadastros e Lançamentos
*Funcionalidades para alimentar o sistema com alunos e cobranças.*

- [ ] **2.1. Gestão de Alunos (Pré-cadastro pelo Tesoureiro):**
  - Formulário para cadastrar aluno individualmente (Nome, CPF, E-mail, Turma/Matrícula, Senha Provisória).
  - (Opcional/Desejável) Importação de alunos via planilha CSV para facilitar o início do ano.
- [ ] **2.2. Lançamento de Parcelas (Cobranças) em Lote e Individual:**
  - Selecionar todos os alunos ativos (ou filtrar por turma) e gerar uma cobrança mensal de uma só vez (definindo Mês de Referência, Valor e Data de Vencimento).
  - Abatimento automático na criação caso o aluno já possua `saldo_credito > 0`.
- [ ] **2.3. Configuração da Chave PIX da Atlética:**
  - Tela simples para o Tesoureiro definir/atualizar a Chave PIX da Atlética, nome do recebedor e cidade (usados na geração do QR Code PIX Estático).

---

## Fase 3: Módulo do Aluno — Portal de Consulta, PIX e Envio de Comprovantes
*Interface focada em celular para os membros da atlética.*

- [ ] **3.1. Meu Painel (Visão do Aluno):**
  - Card de resumo mostrando: **Saldo do Aluno** (positivo de crédito ou negativo pendente), total pendente em parcelas e alertas de parcelas atrasadas.
  - Lista de parcelas separadas por mês com status claro (`Pendente`, `Atrasado`, `Pago`) e indicador se há comprovante `Aguardando Aprovação`.
  - Exibição detalhada de parcelas parciais (ex: *"Valor Total: R$ 100 | Pago: R$ 40 | Pendente: R$ 60 — 1 de 3 pagamentos utilizados"*).
- [ ] **3.2. Gerador de PIX Estático (QR Code + Copia e Cola) e Upload de Comprovante:**
  - Seleção da parcela a pagar + preenchimento do valor pago.
  - **Trava de 1 pagamento por vez:** bloqueia novo envio caso o aluno já possua um pagamento com status `Aguardando Aprovação` (liberando somente após o tesoureiro aprovar ou recusar).
  - Geração instantânea na tela do **QR Code PIX Estático** e botão **"Pix Copia e Cola"** (padrão BR Code do Banco Central, 100% gratuito) já com o valor informado e a chave da Atlética.
  - Limite de até 3 pagamentos por parcela (caso o 3º pagamento seja menor que o valor restante da parcela, avisa que a diferença será lançada como **saldo negativo** após aprovação).
  - **Compressão automática no navegador** caso o anexo seja Imagem (JPG/PNG $\rightarrow$ WebP leve).
  - **Validação de tamanho máximo** (ex: 500 KB) caso o anexo seja arquivo PDF.
- [ ] **3.3. Galeria "Meus Comprovantes":**
  - Tela onde o aluno visualiza todos os comprovantes que já enviou, o status de cada um (`Em análise`, `Aprovado`, `Recusado` + motivo da recusa) e pode abrir o arquivo (se ainda não tiver sido expurgado pela regra de 6-12 meses).

---

## Fase 4: Motor Financeiro e Aprovação pelo Tesoureiro (Coração do Sistema)
*Regras críticas de validação, cascata, saldo e auditoria.*

- [ ] **4.1. Fila de Aprovação de Pagamentos:**
  - Tela para o tesoureiro listar todos os pagamentos com status `Aguardando Aprovação`.
  - Visualizador rápido do comprovante (imagem ou PDF) lado a lado com o valor informado pelo aluno (e alerta caso o hash do comprovante seja duplicado).
- [ ] **4.2. Lógica de Aprovação (Transação SQL / RPC `aprovar_pagamento` pronta em `schema.sql` — falta integrar na UI):**
  - Ao clicar em **Aprovar** (sempre utilizando exatamente o `valor_informado` pelo aluno):
    1. Registra auditoria (`avaliado_por`, `data_avaliacao`, log em `logs_auditoria`).
    2. **Quitação de Saldo Negativo Anterior (Opção A):** Se o aluno possuir `saldo_credito < 0`, utiliza primeiro o valor do pagamento para abater/zerar o saldo negativo antes de alocar nas parcelas (se o pagamento for 100% consumido pelo saldo negativo, ele não consome tentativa da parcela alvo).
    3. Abate o valor restante na parcela alvo. Se for o 1º ou 2º pagamento parcial, mantém a parcela como `Pendente` e atualiza o `valor_pago_acumulado`.
    4. **Regra do 3º Pagamento Menor (Saldo Negativo):** Se for o 3º pagamento da parcela alvo e o valor for menor que o valor restante, encerra a parcela como `Pago` (mantendo `valor_pago_acumulado < valor_original` com a soma real paga) e desconta a diferença faltante de `perfis.saldo_credito` (gerando saldo negativo).
    5. **Regra do Excedente em Cascata:** Se o valor aprovado superar o saldo devedor da parcela atual, quita a parcela atual (`Pago`) e distribui o excedente nas próximas parcelas pendentes do aluno em **ordem cronológica de vencimento** (parando se encontrar uma parcela futura que já tenha 2 pagamentos e o excedente não a quite).
    6. **Regra de Geração de Saldo Positivo:** Se todas as parcelas pendentes do aluno forem quitadas (ou a cascata parar) e ainda sobrar valor, soma o restante em `perfis.saldo_credito`.
- [ ] **4.3. Lógica de Recusa e Gestão de Rejeitados (RPC `recusar_pagamento`):**
  - Ao clicar em **Recusar**: exige preenchimento do motivo da recusa e permite ao tesoureiro **atualizar o valor do envio (`valor_informado`) somente na recusa** caso o comprovante apresente valor divergente, mantendo o comprovante salvo como histórico de rejeição e registrando tudo na auditoria.
  - Botão para o tesoureiro **excluir definitivamente o arquivo** de um comprovante rejeitado quando não for mais necessário.

---

## Fase 5: Relatórios, Organização de Arquivos e Retenção (Storage 90%)
*Gestão a longo prazo, prestação de contas e manutenção do plano gratuito.*

- [ ] **5.1. Painel Geral e Relatório de Inadimplência:**
  - Visão matricial/tabela por **Mês** e por **Aluno**.
  - Filtro rápido: *"Mostrar apenas quem está devendo"* (diferenciando `Pendente no prazo` de `Atrasado/Vencido`), exibindo qual mês deve e o valor exato em aberto.
  - Exportação do relatório de devedores para CSV/Excel ou PDF.
- [ ] **5.2. Explorador de Comprovantes do Tesoureiro:**
  - Visualização de todos os comprovantes separados e filtráveis por **Mês** e por **Aluno**.
- [ ] **5.3. Monitor de Armazenamento, Backup Local e Expurgo Automático (Regra dos 90%):**
  - Barra de uso do Storage no painel do tesoureiro (calculando soma de `comprovante_tamanho_bytes` vs. limite de 1 GB).
  - **Botão de Backup Local:** Permite ao tesoureiro baixar um arquivo `.zip` com os comprovantes de um período/semestre para guardar no computador/HD externo.
  - **Rotina de Limpeza (6 a 12 meses):** Quando o armazenamento atingir $\ge 90\%$, habilitar ação (ou job agendado) que apaga do Supabase Storage os arquivos com mais de 6 a 12 meses, marcando `arquivo_excluido = true` no banco sem apagar os registros contábeis.

---

## Fase Futura (Plano de Estudos Pessoal — Sem auxílio de LLM)
*Para consolidar aprendizado de Engenharia de Software, Python e Banco de Dados.*

- [ ] **Estudo 1 (Opção 4 Local):** Recriar o motor financeiro (regras de parcelas, até 3 parciais, cascata e saldo) usando **Python puro + POO + SQLite** rodando localmente sem ajuda de IA.
- [ ] **Estudo 2 (Opção 3 Autoral):** Construir uma versão web própria sem geração de código por IA para dominar o ciclo completo de requisições HTTP, autenticação e banco de dados.

