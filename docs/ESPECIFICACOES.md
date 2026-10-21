# Especificações do Projeto — Sistema de Controle de Pagamentos da Atlética

> **Propósito deste documento:** Servir como Fonte da Verdade (*Source of Truth*) de regras de negócio, arquitetura e modelagem de dados para orientar o desenvolvimento (humano e assistido por LLMs como Claude Sonnet/Opus).

---

## 1. Visão Geral do Sistema
Aplicação Web Serverless gratuita e de código aberto para gerenciar mensalidades, cobranças, comprovantes de pagamento e saldo de alunos de uma Atlética de Medicina. O sistema possui controle de acesso baseado em perfis (**Tesoureiro/Admin** e **Aluno/Membro**) e trilha completa de auditoria financeira.

---

## 2. Stack Tecnológica e Arquitetura

* **Arquitetura:** Aplicação Web Moderna Serverless (Fullstack), estruturada diretamente na raiz do repositório.
* **Frontend & Rotas de API (BFF):** Next.js (App Router) + React + TypeScript, com segregação de rotas por perfil (`/login`, `/primeiro-acesso`, `/redefinir-senha`, `/admin` e `/aluno`).
* **Estilização:** Tailwind CSS (foco em interface limpa e responsiva/Mobile-first para os alunos enviarem comprovantes pelo celular).
* **Backend-as-a-Service (BaaS):** Supabase
  * **Banco de Dados:** PostgreSQL (Relacional / SQL).
  * **Autenticação:** Supabase Auth (E-mail/Senha com flag de troca obrigatória de senha no primeiro acesso, recuperação de senha via link por e-mail e reset manual de senha provisória pelo Tesoureiro).
  * **Segurança de Dados:** Row Level Security (RLS) ativo em todas as tabelas.
  * **Armazenamento de Arquivos:** Supabase Storage (Bucket privado para comprovantes, organizado virtualmente por `ano-mes/aluno_id/`).
* **Backup & Retenção:** Funcionalidade de exportação/backup local de arquivos pelo Tesoureiro e limpeza de comprovantes antigos quando o Storage atingir $\ge 90\%$ da cota gratuita (1 GB).

---

## 3. Perfis de Usuário e Permissões (RBAC)

### 3.1. Tesoureiro (Administrador)
* Cadastra novos alunos **individualmente** (gerando credenciais provisórias sem exigir confirmação prévia de e-mail, exibindo na tela no momento da criação o card com botão **"Copiar credenciais para WhatsApp"** contendo a URL do site, e-mail e senha provisória).
* Possui o botão **"Resetar Senha Provisória"** em 1 clique caso o aluno esqueça a senha (ou caso o tesoureiro precise reenviar o acesso), gerando uma nova senha temporária exibida na hora com botão de copiar para WhatsApp + URL do site e voltando `precisa_trocar_senha = true` (nenhuma senha fica armazenada em texto no banco).
* Lança cobranças/parcelas individuais ou **em lote** (através de tela com lista de alunos ativos, filtro por turma, botão *"Selecionar Todos"* e checkboxes individuais para incluir/desmarcar alunos específicos no lote).
* Visualiza o painel geral (Dashboard) com filtros por mês, aluno e status (`Pendente`, `Atrasado`, `Em Análise`, `Pago`).
* Aprova ou recusa pagamentos enviados pelos alunos (gerando registro de auditoria automático). **O tesoureiro não altera o valor ao aprovar; caso o valor do comprovante seja diferente do digitado pelo aluno, o tesoureiro recusa o envio e pode atualizar o valor informado (somente na recusa).**
* Exclui comprovantes rejeitados quando necessário.
* Visualiza e baixa comprovantes organizados por aluno e por mês.
* Extrai relatórios de inadimplência (quem deve, qual mês, valor pendente).
* Executa backup local de comprovantes e aciona limpeza de arquivos antigos.

### 3.2. Aluno (Membro Comum)
* No primeiro login (ou após um reset pelo tesoureiro), é **obrigado a redefinir a senha temporária** em `/primeiro-acesso`, respeitando a regra de complexidade forte: **mínimo de 8 caracteres, contendo pelo menos 1 letra maiúscula, 1 letra minúscula, 1 número e 1 símbolo especial** (mais confirmação de senha idêntica).
* Pode recuperar sua senha de forma autônoma na tela de login clicando em **"Esqueci minha senha"** (recebendo link de redefinição por e-mail do Supabase) ou solicitando uma nova senha provisória ao Tesoureiro.
* Visualiza **exclusivamente** suas próprias parcelas, seu histórico de pagamentos, seus comprovantes anexados e seu **saldo de crédito** atual.
* Gera o **QR Code PIX Estático e o código "Pix Copia e Cola"** direto pelo aplicativo (com o valor exato da parcela ou do pagamento parcial desejado, apontando para a chave PIX oficial da Atlética).
* Envia comprovantes de pagamento manualmente após realizar o PIX (PDF com tamanho limite ou Imagem comprimida automaticamente no navegador antes do upload).

---

## 4. Regras de Negócio Financeiras (Core Domain)

### 4.1. Status de uma Parcela (Cobrança)
Uma parcela possui um `valor_original` (ex: R$ 100,00), um `valor_pago_acumulado` (soma exata apenas dos pagamentos **aprovados** vinculados a ela) e uma `data_vencimento`.
1. **Pendente:** `status == 'pendente'` (`valor_pago_acumulado < valor_original`) e `data_atual <= data_vencimento`. (Mesmo que haja pagamento parcial aprovado ou pagamento aguardando aprovação, a parcela segue constando como pendente do valor restante).
2. **Atrasado:** `status == 'pendente'` (`valor_pago_acumulado < valor_original`) e `data_atual > data_vencimento`.
3. **Pago:** `status == 'pago'` (atingido quando `valor_pago_acumulado == valor_original` **ou** quando o 3º pagamento aprovado é menor que o valor restante e a diferença é transferida para o saldo negativo do aluno, mantendo `valor_pago_acumulado < valor_original`).

> **Trava de 1 Pagamento por Vez:** O aluno só pode ter **1 pagamento com status `Aguardando Aprovação` por vez**. Enquanto o tesoureiro não aprovar ou recusar o envio atual, o sistema bloqueia o envio de novos comprovantes pelo aluno.

### 4.2. Status de um Pagamento (Transação/Comprovante)
1. **Aguardando Aprovação (Em Análise):** Estado inicial assim que o aluno envia o comprovante. **Ainda não abate** o valor definitivo da parcela até que o tesoureiro valide.
2. **Aprovado:** Validado pelo tesoureiro. O valor abatido é **exatamente o `valor_informado` pelo aluno** (o tesoureiro não edita valores na aprovação). Dispara a regra de abatimento em cascata e saldo (Seção 4.3). Registra metadados de auditoria (`avaliado_por`, `data_avaliacao`).
3. **Recusado (Negado):** Rejeitado pelo tesoureiro (com justificativa). Caso o pagamento seja de um valor diferente do comprovante, **o tesoureiro pode atualizar o `valor_informado` do envio (somente quando recusado)**, registrando na auditoria o valor original e o valor corrigido. Não abate valores nas parcelas. O comprovante permanece salvo como evidência de rejeição, mas habilita a opção para o tesoureiro excluí-lo do Storage posteriormente.

### 4.3. Abatimento, Pagamento Parcial, Cascata e Saldo do Aluno
Para conciliar a regra de *"O pagamento gera saldo que abate parcelas"* com *"Até 3 pagamentos por parcela"* e *"Excedente desconta parcelas futuras"*:

1. **Limite de 3 Pagamentos por Parcela e Saldo Negativo no 3º Pagamento:**
   * Uma parcela pode receber no máximo **3 alocações de pagamento**.
   * Caso o **3º pagamento** da parcela alvo seja **menor** que o valor restante (`valor_pendente`), a parcela é encerrada como `Pago` (mantendo `valor_pago_acumulado` com a soma real paga, ou seja, `valor_pago_acumulado < valor_original`) e a diferença faltante (`valor_pendente - valor_3o_pagamento`) é abatida de `saldo_credito` do aluno, **gerando saldo negativo**.
   * **Quitação Automática do Saldo Negativo no Próximo Pagamento:** Caso o aluno possua `saldo_credito < 0` (saldo negativo) ao ter um novo pagamento aprovado, o sistema **primeiro utiliza o valor do pagamento para abater/zerar esse saldo negativo** e, em seguida, aplica o valor restante na parcela alvo e nas demais parcelas em aberto. Se o pagamento for 100% consumido para cobrir o saldo negativo anterior (`valor_restante == 0`), ele apenas abate o saldo negativo e **não consome** uma das 3 tentativas da parcela alvo.
2. **Pagamento Excedente (Efeito Cascata Cronológico):**
   * Se o aluno enviar um pagamento cujo valor aprovado supere o `valor_pendente` da parcela atual, o sistema quita a parcela atual (`Pago`) e aplica o valor excedente nas **próximas parcelas em aberto do aluno, em ordem cronológica de vencimento** (`data_vencimento ASC`).
   * Se durante a cascata uma parcela futura já possuir 2 pagamentos parciais e o excedente restante não for suficiente para quitá-la, a cascata para naquele ponto e a sobra vai para o `saldo_credito` do aluno.
3. **Geração de Saldo Positivo (Crédito):**
   * Se após quitar todas as parcelas pendentes existentes ainda sobrar valor do pagamento, esse excedente é somado ao campo `saldo_credito` no cadastro do aluno.
4. **Uso Automático do Saldo em Lançamentos Futuros:**
   * Quando o tesoureiro lançar uma nova parcela (individual ou em lote) para um aluno que possui `saldo_credito > 0`, o sistema abate automaticamente o saldo disponível da nova parcela (quitando-a total ou parcialmente sem necessidade de novo comprovante, registrando a origem como `tipo_origem = 'saldo_credito'`).

### 4.4. Geração de PIX Estático (100% Gratuito via Padrão BR Code)
* O sistema não utiliza API paga de gateway bancário: ele gera localmente o payload **EMV® BR Code (PIX Estático)** a partir da chave PIX configurada pela Atlética.
* Ao selecionar uma parcela e informar o valor a pagar (total ou parcial), o aplicativo exibe instantaneamente:
  1. **Imagem do QR Code PIX** pronta para leitura pela câmera do app bancário.
  2. **Botão "Copiar Código PIX (Copia e Cola)"** e **Botão "Copiar Chave PIX da Atlética"**.
  3. **Identificador (`txid`):** Gerado com até 25 caracteres alfanuméricos identificando o mês/parcela (ex: `ATLETICA202610`).
* Após realizar o pagamento no aplicativo do banco, o aluno anexa manualmente o comprovante na mesma tela para entrar na fila de aprovação do tesoureiro.

---

## 5. Regras de Armazenamento, Arquivos e Ciclo de Vida

1. **Formatos e Limites de Upload:**
   * **Imagens (JPG, PNG, WebP):** Comprimidas no lado do cliente (navegador) antes do envio (meta: $\le 150\text{ KB}$ por imagem, resolução máx. 1600px, formato WebP).
   * **Documentos (PDF):** Permitidos com trava rígida de tamanho máximo (ex: $\le 500\text{ KB}$).
2. **Organização Lógica:**
   * Caminho padrão no Storage: `comprovantes/{ano}-{mes}/{usuario_id}/{pagamento_id}.{ext}`.
3. **Política de Retenção e Limpeza (Gatilho de 90%):**
   * Monitoramento do uso do bucket do Supabase Storage (limite Free Tier = 1 GB).
   * Caso o armazenamento atinja $\ge 90\%$ ($\sim 900\text{ MB}$), o sistema alerta o Tesoureiro para:
     1. Baixar um pacote `.zip` de backup local dos comprovantes antigos.
     2. Executar a rotina de expurgo que remove do Storage os arquivos de comprovantes com idade entre **6 e 12 meses** (mantendo os metadados financeiros e de auditoria intactos no banco SQL, marcando `arquivo_excluido = true`).

---

## 6. Diretrizes de Modelagem de Dados (Referência para o Claude)

Para suportar pagamentos parciais (máx. 3 por parcela), cascata em parcelas futuras, saldo remanescente e auditoria, o banco PostgreSQL deve seguir esta estrutura relacional:

1. **`perfis` (vinculada a `auth.users` do Supabase):**
   * `id` (UUID, PK), `nome_completo`, `cpf` (Unique, nullable para criação do 1º admin via Dashboard), `email`, `matricula_ou_turma`, `role` (`'admin' | 'aluno'`), `precisa_trocar_senha` (Boolean, default `true`), `saldo_credito` (Numeric(10,2), default `0.00` — aceita valores positivos, zero ou **negativos** quando o 3º pagamento de uma parcela for menor que o restante), `ativo` (Boolean, default `true` — alunos com histórico são desativados e não excluídos), `created_at`.
   *(Nota de Segurança: O aluno não possui permissão de `UPDATE` direto em `perfis`; a marcação de troca de senha ocorre via função RPC `marcar_senha_trocada()`).*
2. **`parcelas` (Cobranças geradas individualmente ou em lote):**
   * `id` (UUID, PK), `aluno_id` (FK -> `perfis.id`), `descricao` (ex: "Mensalidade Outubro/2026"), `mes_referencia` (ex: `'2026-10'`), `valor_original` (Numeric(10,2)), `valor_pago_acumulado` (Numeric(10,2), default `0.00`), `data_vencimento` (Date), `status` (`'pendente' | 'pago'`), `lote_id` (UUID opcional para rastrear lançamentos em lote), `criado_por` (FK -> `perfis.id`), `created_at`.
   *(Nota: O estado "Atrasado" é calculado via View SQL `vw_parcelas_situacao` considerando o fuso `America/Sao_Paulo` quando `status = 'pendente'` e `data_vencimento < data_atual_brasilia`).*
3. **`pagamentos` (Envio do comprovante pelo aluno):**
   * `id` (UUID, PK), `aluno_id` (FK -> `perfis.id`), `parcela_alvo_inicial_id` (FK -> `parcelas.id`, opcional), `valor_informado` (Numeric(10,2) — atualizado apenas se o tesoureiro corrigir o valor no momento da recusa), `data_pagamento` (Date, validada no fuso `America/Sao_Paulo`), `comprovante_path` (Text), `comprovante_mime_type` (`'image/webp' | 'application/pdf'`), `comprovante_tamanho_bytes` (Int), `comprovante_hash` (Text, opcional, SHA-256 para detecção de comprovantes duplicados), `arquivo_excluido` (Boolean, default `false` — ao mudar para `true`, um trigger grava automaticamente `EXCLUSAO_COMPROVANTE` em `logs_auditoria`), `status_validacao` (`'aguardando' | 'aprovado' | 'recusado'`), `motivo_recusa` (Text, nullable), `avaliado_por` (FK -> `perfis.id`, nullable), `data_avaliacao` (Timestamptz, nullable), `created_at`.
   *(Nota: Existe um índice único parcial por `aluno_id` onde `status_validacao = 'aguardando'`, garantindo no banco que o aluno só pode ter 1 pagamento em análise por vez. A aprovação e a recusa são executadas exclusivamente via funções transacionais `aprovar_pagamento(p_pagamento_id)` e `recusar_pagamento(p_pagamento_id, p_motivo, p_valor_corrigido)`).*
4. **`alocacoes_pagamento` (Tabela associativa N:N que liga Pagamentos Aprovados/Saldo às Parcelas):**
   * `id` (UUID, PK), `parcela_id` (FK -> `parcelas.id`), `pagamento_id` (FK -> `pagamentos.id`, nullable se veio de saldo anterior), `tipo_origem` (`'comprovante' | 'saldo_credito'`), `valor_alocado` (Numeric(10,2)), `created_at`.
   *(Garante a regra de até 3 pagamentos por parcela contando quantas alocações existem para um `parcela_id`, e permite que 1 pagamento quite N parcelas em ordem cronológica).*
5. **`logs_auditoria` (Trilha imutável de ações críticas):**
   * `id` (UUID, PK), `ator_id` (FK -> `perfis.id`), `acao` (ex: `'APROVACAO_PAGAMENTO'`, `'RECUSA_PAGAMENTO'`, `'EXCLUSAO_COMPROVANTE'`, `'LANCAMENTO_LOTE'`), `entidade_afetada` (Text), `entidade_id` (UUID), `detalhes_json` (JSONB), `created_at`.
6. **`configuracoes_atletica` (Dados do PIX Estático da Atlética):**
   * `id` (Int, PK, registro único), `chave_pix` (Text), `tipo_chave` (`'cpf' | 'cnpj' | 'email' | 'telefone' | 'aleatoria'`), `nome_beneficiario` (Text, máx. 25 caracteres sem acento para padrão BR Code), `cidade_beneficiario` (Text, máx. 15 caracteres), `updated_at`, `atualizado_por` (FK -> `perfis.id`).

