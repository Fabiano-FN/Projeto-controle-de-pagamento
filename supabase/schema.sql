-- =============================================================================
-- Sistema de Controle de Pagamentos da Atlética — Schema Supabase (PostgreSQL)
-- =============================================================================
-- Cobre os itens 1.1, 1.2 e 1.3 da Fase 1 (ver FUNCIONALIDADES.md):
--   1.1 Tabelas, chaves estrangeiras e constraints
--   1.2 Row Level Security (RLS)
--   1.3 Bucket privado "comprovantes" no Supabase Storage
-- Também inclui as funções do motor financeiro (Seção 4.3 de ESPECIFICACOES.md).
--
-- COMO EXECUTAR: Supabase Dashboard -> SQL Editor -> colar tudo -> Run.
-- Pensado para rodar UMA VEZ em um projeto novo (não é idempotente).
--
-- CONVENÇÕES:
--   * Valores monetários: numeric(10,2) (nunca float, para não perder centavos).
--   * Escritas sensíveis (aprovar, recusar, abater saldo) só acontecem via
--     funções SECURITY DEFINER, que validam permissão e regras de negócio.
--   * search_path = '' nas funções: obriga nomes qualificados (public.x),
--     evitando ataques de sequestro de search_path.
-- =============================================================================


-- =============================================================================
-- 1. TABELAS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1.1 perfis — dados do usuário, ligados 1:1 a auth.users
-- -----------------------------------------------------------------------------
create table public.perfis (
  id                   uuid primary key references auth.users (id) on delete cascade,
  nome_completo        text not null check (char_length(nome_completo) between 2 and 150),
  -- CPF só com dígitos. Nullable para permitir criar o 1º admin pelo Dashboard.
  cpf                  text unique check (cpf ~ '^[0-9]{11}$'),
  email                text not null unique,
  matricula_ou_turma   text,
  role                 text not null default 'aluno' check (role in ('admin', 'aluno')),
  precisa_trocar_senha boolean not null default true,
  -- Pode ficar negativo caso o 3º pagamento de uma parcela seja menor que o restante
  saldo_credito        numeric(10,2) not null default 0.00,
  ativo                boolean not null default true,
  created_at           timestamptz not null default now()
);

comment on table public.perfis is 'Perfil de cada usuário (tesoureiro/admin ou aluno). Desative com ativo=false em vez de excluir.';

-- -----------------------------------------------------------------------------
-- 1.2 parcelas — cobranças lançadas pelo tesoureiro (individual ou em lote)
-- -----------------------------------------------------------------------------
create table public.parcelas (
  id                   uuid primary key default gen_random_uuid(),
  aluno_id             uuid not null references public.perfis (id) on delete restrict,
  descricao            text not null,
  mes_referencia       text not null check (mes_referencia ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  valor_original       numeric(10,2) not null check (valor_original > 0),
  valor_pago_acumulado numeric(10,2) not null default 0.00,
  data_vencimento      date not null,
  status               text not null default 'pendente' check (status in ('pendente', 'pago')),
  lote_id              uuid,  -- agrupa parcelas criadas no mesmo lançamento em lote
  criado_por           uuid references public.perfis (id) on delete restrict,
  created_at           timestamptz not null default now(),

  constraint parcelas_pago_entre_zero_e_total
    check (valor_pago_acumulado >= 0 and valor_pago_acumulado <= valor_original),
  -- Se está pendente, valor_pago_acumulado é menor que valor_original.
  -- Se está pago, valor_pago_acumulado pode ser igual a valor_original (quitada integralmente)
  -- ou menor que valor_original (quando encerrada no 3º pagamento gerando saldo negativo).
  constraint parcelas_status_coerente
    check (status = 'pago' or valor_pago_acumulado < valor_original)
);

create index parcelas_aluno_status_venc_idx on public.parcelas (aluno_id, status, data_vencimento);
create index parcelas_mes_idx on public.parcelas (mes_referencia);
create index parcelas_lote_idx on public.parcelas (lote_id) where lote_id is not null;

-- -----------------------------------------------------------------------------
-- 1.3 pagamentos — comprovante enviado pelo aluno
-- -----------------------------------------------------------------------------
-- Dica para o frontend: gere o id no cliente (crypto.randomUUID()) para montar
-- o caminho do arquivo no Storage antes de inserir a linha.
create table public.pagamentos (
  id                        uuid primary key default gen_random_uuid(),
  aluno_id                  uuid not null references public.perfis (id) on delete restrict,
  parcela_alvo_inicial_id   uuid references public.parcelas (id) on delete restrict,
  -- Valor informado pelo aluno (só pode ser atualizado pelo tesoureiro no ato da recusa)
  valor_informado           numeric(10,2) not null check (valor_informado > 0),
  data_pagamento            date not null check (data_pagamento <= (now() at time zone 'America/Sao_Paulo')::date),
  comprovante_path          text,  -- caminho no bucket: {ano}-{mes}/{aluno_id}/{pagamento_id}.{ext}
  comprovante_mime_type     text check (comprovante_mime_type in ('image/webp', 'application/pdf')),
  comprovante_tamanho_bytes integer check (comprovante_tamanho_bytes between 1 and 512000),
  comprovante_hash          text,  -- opcional: SHA-256 do arquivo para detectar duplicados
  arquivo_excluido          boolean not null default false,  -- true após expurgo/exclusão do arquivo
  status_validacao          text not null default 'aguardando'
                              check (status_validacao in ('aguardando', 'aprovado', 'recusado')),
  motivo_recusa             text,
  avaliado_por              uuid references public.perfis (id) on delete restrict,
  data_avaliacao            timestamptz,
  created_at                timestamptz not null default now(),

  constraint pagamentos_recusa_exige_motivo
    check (status_validacao <> 'recusado' or char_length(coalesce(motivo_recusa, '')) >= 3),
  constraint pagamentos_avaliacao_coerente
    check ((status_validacao = 'aguardando') = (avaliado_por is null and data_avaliacao is null))
);

create index pagamentos_aluno_idx on public.pagamentos (aluno_id, created_at desc);
create index pagamentos_status_idx on public.pagamentos (status_validacao, created_at);
create index pagamentos_parcela_alvo_idx on public.pagamentos (parcela_alvo_inicial_id);
create index pagamentos_hash_idx on public.pagamentos (comprovante_hash) where comprovante_hash is not null;
-- Garante que o aluno só pode ter 1 pagamento aguardando aprovação por vez
create unique index pagamentos_um_aguardando_por_aluno_idx
  on public.pagamentos (aluno_id) where status_validacao = 'aguardando';

-- -----------------------------------------------------------------------------
-- 1.4 alocacoes_pagamento — quanto de cada pagamento/saldo foi para cada parcela
-- -----------------------------------------------------------------------------
-- 1 pagamento -> N parcelas (cascata); 1 parcela -> até 3 alocações.
create table public.alocacoes_pagamento (
  id            uuid primary key default gen_random_uuid(),
  parcela_id    uuid not null references public.parcelas (id) on delete restrict,
  pagamento_id  uuid references public.pagamentos (id) on delete restrict,
  tipo_origem   text not null check (tipo_origem in ('comprovante', 'saldo_credito')),
  valor_alocado numeric(10,2) not null check (valor_alocado > 0),
  created_at    timestamptz not null default now(),

  constraint alocacoes_origem_coerente check (
    (tipo_origem = 'comprovante'   and pagamento_id is not null) or
    (tipo_origem = 'saldo_credito' and pagamento_id is null)
  )
);

create index alocacoes_parcela_idx on public.alocacoes_pagamento (parcela_id);
create index alocacoes_pagamento_idx on public.alocacoes_pagamento (pagamento_id);

-- -----------------------------------------------------------------------------
-- 1.5 logs_auditoria — trilha imutável de ações críticas
-- -----------------------------------------------------------------------------
create table public.logs_auditoria (
  id               uuid primary key default gen_random_uuid(),
  ator_id          uuid references public.perfis (id) on delete restrict,  -- null = sistema/service_role
  acao             text not null,  -- APROVACAO_PAGAMENTO, RECUSA_PAGAMENTO, ABATIMENTO_SALDO, ...
  entidade_afetada text not null,
  entidade_id      uuid,
  detalhes_json    jsonb not null default '{}'::jsonb,
  created_at       timestamptz not null default now()
);

create index logs_entidade_idx on public.logs_auditoria (entidade_afetada, entidade_id);
create index logs_created_idx on public.logs_auditoria (created_at desc);

-- -----------------------------------------------------------------------------
-- 1.6 configuracoes_atletica — dados do PIX estático (registro único, id = 1)
-- -----------------------------------------------------------------------------
create table public.configuracoes_atletica (
  id                  integer primary key default 1 check (id = 1),
  chave_pix           text,
  tipo_chave          text check (tipo_chave in ('cpf', 'cnpj', 'email', 'telefone', 'aleatoria')),
  nome_beneficiario   text check (char_length(nome_beneficiario) <= 25),
  cidade_beneficiario text check (char_length(cidade_beneficiario) <= 15),
  updated_at          timestamptz not null default now(),
  atualizado_por      uuid references public.perfis (id) on delete restrict
);

insert into public.configuracoes_atletica (id) values (1);


-- =============================================================================
-- 2. VIEW — situação calculada da parcela (inclui "atrasado")
-- =============================================================================
-- security_invoker = true: a view respeita o RLS de quem consulta.
create view public.vw_parcelas_situacao
with (security_invoker = true) as
select
  p.*,
  case
    when p.status = 'pago' then 0.00
    else (p.valor_original - p.valor_pago_acumulado)
  end::numeric(10,2) as valor_pendente,
  case
    when p.status = 'pago' then (p.valor_original - p.valor_pago_acumulado)
    else 0.00
  end::numeric(10,2) as valor_transferido_saldo_negativo,
  case
    when p.status = 'pago'                   then 'pago'
    -- o banco do Supabase roda em UTC; usamos o fuso de Brasília para não marcar
    -- "atrasado" 3h antes da virada do dia
    when p.data_vencimento < (now() at time zone 'America/Sao_Paulo')::date then 'atrasado'
    else 'pendente'
  end as situacao,
  (select count(*) from public.alocacoes_pagamento a where a.parcela_id = p.id)::int as qtd_alocacoes,
  exists (
    select 1 from public.pagamentos pg
    where pg.parcela_alvo_inicial_id = p.id and pg.status_validacao = 'aguardando'
  ) as tem_pagamento_em_analise
from public.parcelas p;


-- =============================================================================
-- 3. FUNÇÕES AUXILIARES
-- =============================================================================

-- Retorna true se o usuário logado é admin ativo.
-- SECURITY DEFINER evita recursão infinita de RLS ao consultar perfis.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfis
    where id = auth.uid() and role = 'admin' and ativo
  );
$$;

-- Cria o perfil automaticamente quando um usuário é criado no Supabase Auth.
-- O tesoureiro (Fase 2) deve criar o usuário enviando user_metadata:
--   { "nome_completo": "...", "cpf": "12345678901", "matricula_ou_turma": "..." }
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.perfis (id, email, nome_completo, cpf, matricula_ou_turma)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'nome_completo', ''), new.email),
    nullif(new.raw_user_meta_data ->> 'cpf', ''),
    nullif(new.raw_user_meta_data ->> 'matricula_ou_turma', '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Aluno marca que já trocou a senha provisória (usado no item 1.4).
-- Aluno não tem permissão de UPDATE em perfis; por isso existe esta função.
create or replace function public.marcar_senha_trocada()
returns void
language sql
security definer
set search_path = ''
as $$
  update public.perfis set precisa_trocar_senha = false where id = auth.uid();
$$;

-- Logs de auditoria são imutáveis.
create or replace function public.bloquear_alteracao_log()
returns trigger
language plpgsql
as $$
begin
  raise exception 'logs_auditoria é imutável (operação % bloqueada)', tg_op;
end;
$$;

create trigger logs_auditoria_imutavel
  before update or delete on public.logs_auditoria
  for each row execute function public.bloquear_alteracao_log();

-- Defesa em profundidade: no máximo 3 alocações por parcela.
create or replace function public.validar_limite_alocacoes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select count(*) from public.alocacoes_pagamento where parcela_id = new.parcela_id) >= 3 then
    raise exception 'A parcela % já possui 3 pagamentos (limite atingido)', new.parcela_id;
  end if;
  return new;
end;
$$;

create trigger alocacoes_limite_3
  before insert on public.alocacoes_pagamento
  for each row execute function public.validar_limite_alocacoes();

-- Validação no envio do comprovante (antes de chegar ao tesoureiro):
--   * o aluno só pode ter 1 pagamento aguardando aprovação por vez;
--   * parcela alvo precisa ser do próprio aluno e estar pendente;
--   * respeita o limite máximo de 3 pagamentos por parcela (se o 3º pagamento for
--     menor que o valor restante, a diferença virará saldo negativo na aprovação).
create or replace function public.validar_novo_pagamento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parcela   public.parcelas%rowtype;
  v_qtd       integer;
begin
  if exists (
    select 1 from public.pagamentos
    where aluno_id = new.aluno_id and status_validacao = 'aguardando'
  ) then
    raise exception 'Você já possui um pagamento aguardando aprovação do tesoureiro. Aguarde a avaliação antes de enviar outro.';
  end if;

  if new.parcela_alvo_inicial_id is null then
    return new;
  end if;

  select * into v_parcela from public.parcelas where id = new.parcela_alvo_inicial_id;

  if not found or v_parcela.aluno_id <> new.aluno_id then
    raise exception 'Parcela alvo inválida para este aluno';
  end if;

  if v_parcela.status = 'pago' then
    raise exception 'Esta parcela já está paga';
  end if;

  select count(*) into v_qtd
  from public.alocacoes_pagamento
  where parcela_id = v_parcela.id;

  if v_qtd >= 3 then
    raise exception 'Limite de 3 pagamentos por parcela atingido';
  end if;

  return new;
end;
$$;

create trigger pagamentos_validar_insert
  before insert on public.pagamentos
  for each row execute function public.validar_novo_pagamento();

-- Registra automaticamente na auditoria quando um arquivo de comprovante é excluído
-- (seja um comprovante recusado ou via expurgo de 90%).
create or replace function public.registrar_exclusao_comprovante()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.arquivo_excluido = false and new.arquivo_excluido = true then
    insert into public.logs_auditoria (ator_id, acao, entidade_afetada, entidade_id, detalhes_json)
    values (
      auth.uid(),
      'EXCLUSAO_COMPROVANTE',
      'pagamentos',
      new.id,
      jsonb_build_object(
        'aluno_id',         new.aluno_id,
        'status_validacao', new.status_validacao,
        'comprovante_path', old.comprovante_path,
        'tamanho_bytes',    old.comprovante_tamanho_bytes
      )
    );
  end if;
  return new;
end;
$$;

create trigger pagamentos_log_exclusao_comprovante
  after update of arquivo_excluido on public.pagamentos
  for each row execute function public.registrar_exclusao_comprovante();


-- =============================================================================
-- 4. MOTOR FINANCEIRO (Seção 4.3)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 4.1 aprovar_pagamento — chamada pelo tesoureiro via supabase.rpc(...)
-- -----------------------------------------------------------------------------
-- O tesoureiro aprova exatamente o valor_informado pelo aluno (não edita valores na aprovação).
-- Ordem de abatimento:
--   0º se o aluno tiver saldo negativo (saldo_credito < 0), abate primeiro essa dívida;
--   1º a parcela alvo (se informada e pendente);
--   depois as demais pendentes do aluno por data_vencimento ASC (cascata);
--   a sobra vira saldo_credito positivo.
-- Regra dos 3 pagamentos:
--   * Se for a 3ª alocação da parcela ALVO e o valor for menor que o restante (v_pendente),
--     a parcela é encerrada como 'pago' e a diferença faltante é abatida de saldo_credito
--     (gerando saldo negativo para o aluno).
--   * Se na CASCATA uma parcela futura já tiver 2 alocações e o valor não a quitar,
--     a cascata para ali e o restante vira saldo_credito.
-- Tudo roda em uma única transação: se algo falhar, nada é gravado.
create or replace function public.aprovar_pagamento(
  p_pagamento_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_id               uuid := auth.uid();
  v_pag                    public.pagamentos%rowtype;
  v_saldo_atual            numeric(10,2);
  v_restante               numeric(10,2);
  v_parcela                record;
  v_pendente               numeric(10,2);
  v_qtd_aloc               integer;
  v_valor_aloc             numeric(10,2);
  v_faltante               numeric(10,2);
  v_alocacoes              jsonb := '[]'::jsonb;
  v_saldo_negativo_quitado numeric(10,2) := 0;
  v_saldo_gerado           numeric(10,2) := 0;
  v_saldo_negativo_gerado  numeric(10,2) := 0;
begin
  if not public.is_admin() then
    raise exception 'Apenas o tesoureiro pode aprovar pagamentos' using errcode = '42501';
  end if;

  -- trava o pagamento para evitar aprovação dupla simultânea
  select * into v_pag from public.pagamentos where id = p_pagamento_id for update;
  if not found then
    raise exception 'Pagamento % não encontrado', p_pagamento_id;
  end if;
  if v_pag.status_validacao <> 'aguardando' then
    raise exception 'Pagamento já foi avaliado (status: %)', v_pag.status_validacao;
  end if;

  v_restante := round(v_pag.valor_informado, 2);

  -- trava o perfil do aluno (saldo) durante a operação
  select saldo_credito into v_saldo_atual
  from public.perfis
  where id = v_pag.aluno_id
  for update;

  -- Opção A: se o aluno possui saldo negativo anterior, quita/abate primeiro essa pendência
  if v_saldo_atual < 0 and v_restante > 0 then
    v_saldo_negativo_quitado := least(v_restante, abs(v_saldo_atual));
    update public.perfis
       set saldo_credito = saldo_credito + v_saldo_negativo_quitado
     where id = v_pag.aluno_id;
    v_restante := v_restante - v_saldo_negativo_quitado;
  end if;

  for v_parcela in
    select p.id, p.valor_original, p.valor_pago_acumulado, p.data_vencimento, p.mes_referencia
    from public.parcelas p
    where p.aluno_id = v_pag.aluno_id
      and p.status = 'pendente'
    order by
      coalesce(p.id = v_pag.parcela_alvo_inicial_id, false) desc,
      p.data_vencimento asc,
      p.created_at asc
    for update
  loop
    exit when v_restante <= 0;

    v_pendente := v_parcela.valor_original - v_parcela.valor_pago_acumulado;
    select count(*) into v_qtd_aloc from public.alocacoes_pagamento where parcela_id = v_parcela.id;

    if v_qtd_aloc >= 3 then
      continue;
    end if;

    -- Caso seja o 3º pagamento da parcela e o valor restante do envio seja menor que o pendente
    if v_qtd_aloc = 2 and v_restante < v_pendente then
      if v_parcela.id = v_pag.parcela_alvo_inicial_id then
        -- 3º pagamento da parcela alvo menor que o restante: encerra a parcela (mantendo
        -- valor_pago_acumulado < valor_original com a soma real paga) e gera saldo negativo
        v_valor_aloc := v_restante;
        v_faltante   := v_pendente - v_restante;

        insert into public.alocacoes_pagamento (parcela_id, pagamento_id, tipo_origem, valor_alocado)
        values (v_parcela.id, v_pag.id, 'comprovante', v_valor_aloc);

        update public.parcelas
           set valor_pago_acumulado = valor_pago_acumulado + v_valor_aloc,
               status               = 'pago'
         where id = v_parcela.id;

        update public.perfis
           set saldo_credito = saldo_credito - v_faltante
         where id = v_pag.aluno_id;

        v_saldo_negativo_gerado := v_faltante;
        v_restante              := 0;
        v_alocacoes             := v_alocacoes || jsonb_build_object(
          'parcela_id',            v_parcela.id,
          'mes_referencia',        v_parcela.mes_referencia,
          'valor_alocado',         v_valor_aloc,
          'saldo_negativo_gerado', v_faltante,
          'quitou',                true
        );
        exit;
      else
        -- Na cascata para parcelas futuras: interrompe a cascata e o restante vira saldo positivo
        exit;
      end if;
    end if;

    v_valor_aloc := least(v_restante, v_pendente);

    insert into public.alocacoes_pagamento (parcela_id, pagamento_id, tipo_origem, valor_alocado)
    values (v_parcela.id, v_pag.id, 'comprovante', v_valor_aloc);

    update public.parcelas
       set valor_pago_acumulado = valor_pago_acumulado + v_valor_aloc,
           status = case when valor_pago_acumulado + v_valor_aloc >= valor_original
                         then 'pago' else 'pendente' end
     where id = v_parcela.id;

    v_restante  := v_restante - v_valor_aloc;
    v_alocacoes := v_alocacoes || jsonb_build_object(
      'parcela_id',     v_parcela.id,
      'mes_referencia', v_parcela.mes_referencia,
      'valor_alocado',  v_valor_aloc,
      'quitou',         v_valor_aloc = v_pendente
    );
  end loop;

  -- sobra -> saldo de crédito positivo do aluno
  if v_restante > 0 then
    update public.perfis set saldo_credito = saldo_credito + v_restante where id = v_pag.aluno_id;
    v_saldo_gerado := v_restante;
  end if;

  update public.pagamentos
     set status_validacao = 'aprovado',
         avaliado_por     = v_admin_id,
         data_avaliacao   = now()
   where id = v_pag.id;

  insert into public.logs_auditoria (ator_id, acao, entidade_afetada, entidade_id, detalhes_json)
  values (
    v_admin_id, 'APROVACAO_PAGAMENTO', 'pagamentos', v_pag.id,
    jsonb_build_object(
      'aluno_id',               v_pag.aluno_id,
      'valor_informado',        v_pag.valor_informado,
      'saldo_negativo_quitado', v_saldo_negativo_quitado,
      'alocacoes',              v_alocacoes,
      'saldo_gerado',           v_saldo_gerado,
      'saldo_negativo_gerado',  v_saldo_negativo_gerado
    )
  );

  return jsonb_build_object(
    'pagamento_id',           v_pag.id,
    'saldo_negativo_quitado', v_saldo_negativo_quitado,
    'alocacoes',              v_alocacoes,
    'saldo_gerado',           v_saldo_gerado,
    'saldo_negativo_gerado',  v_saldo_negativo_gerado
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4.2 recusar_pagamento — mantém o comprovante como evidência e permite
--     atualizar o valor do envio (somente quando recusado)
-- -----------------------------------------------------------------------------
create or replace function public.recusar_pagamento(
  p_pagamento_id    uuid,
  p_motivo          text,
  p_valor_corrigido numeric default null  -- opcional: atualiza valor_informado quando diverge do comprovante
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pag        public.pagamentos%rowtype;
  v_novo_valor numeric(10,2);
begin
  if not public.is_admin() then
    raise exception 'Apenas o tesoureiro pode recusar pagamentos' using errcode = '42501';
  end if;

  select * into v_pag from public.pagamentos where id = p_pagamento_id for update;
  if not found then
    raise exception 'Pagamento % não encontrado', p_pagamento_id;
  end if;
  if v_pag.status_validacao <> 'aguardando' then
    raise exception 'Pagamento já foi avaliado (status: %)', v_pag.status_validacao;
  end if;

  v_novo_valor := round(coalesce(p_valor_corrigido, v_pag.valor_informado), 2);
  if v_novo_valor <= 0 then
    raise exception 'O valor do envio deve ser maior que zero';
  end if;

  update public.pagamentos
     set status_validacao = 'recusado',
         motivo_recusa    = p_motivo,
         valor_informado  = v_novo_valor,
         avaliado_por     = auth.uid(),
         data_avaliacao   = now()
   where id = v_pag.id;

  insert into public.logs_auditoria (ator_id, acao, entidade_afetada, entidade_id, detalhes_json)
  values (
    auth.uid(), 'RECUSA_PAGAMENTO', 'pagamentos', v_pag.id,
    jsonb_build_object(
      'aluno_id',                 v_pag.aluno_id,
      'valor_informado_original', v_pag.valor_informado,
      'valor_atualizado_recusa',  v_novo_valor,
      'motivo',                   p_motivo
    )
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 4.3 Uso automático do saldo ao lançar nova parcela (Seção 4.3, item 4)
-- -----------------------------------------------------------------------------
create or replace function public.aplicar_saldo_em_nova_parcela()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saldo numeric(10,2);
  v_uso   numeric(10,2);
begin
  select saldo_credito into v_saldo from public.perfis where id = new.aluno_id for update;

  if v_saldo is null or v_saldo <= 0 then
    return null;
  end if;

  v_uso := least(v_saldo, new.valor_original);

  insert into public.alocacoes_pagamento (parcela_id, pagamento_id, tipo_origem, valor_alocado)
  values (new.id, null, 'saldo_credito', v_uso);

  update public.parcelas
     set valor_pago_acumulado = valor_pago_acumulado + v_uso,
         status = case when valor_pago_acumulado + v_uso >= valor_original then 'pago' else 'pendente' end
   where id = new.id;

  update public.perfis set saldo_credito = saldo_credito - v_uso where id = new.aluno_id;

  insert into public.logs_auditoria (ator_id, acao, entidade_afetada, entidade_id, detalhes_json)
  values (auth.uid(), 'ABATIMENTO_SALDO', 'parcelas', new.id,
          jsonb_build_object('aluno_id', new.aluno_id, 'valor_usado', v_uso, 'saldo_anterior', v_saldo));

  return null;
end;
$$;

create trigger parcelas_aplicar_saldo
  after insert on public.parcelas
  for each row execute function public.aplicar_saldo_em_nova_parcela();


-- =============================================================================
-- 5. PERMISSÕES DE EXECUÇÃO DAS FUNÇÕES
-- =============================================================================
-- Por padrão o Postgres libera EXECUTE para PUBLIC; restringimos explicitamente.
revoke execute on function public.is_admin()                               from public, anon;
revoke execute on function public.marcar_senha_trocada()                   from public, anon;
revoke execute on function public.aprovar_pagamento(uuid)                  from public, anon;
revoke execute on function public.recusar_pagamento(uuid, text, numeric)   from public, anon;
revoke execute on function public.handle_new_user()                        from public, anon, authenticated;
revoke execute on function public.validar_limite_alocacoes()               from public, anon, authenticated;
revoke execute on function public.validar_novo_pagamento()                 from public, anon, authenticated;
revoke execute on function public.registrar_exclusao_comprovante()         from public, anon, authenticated;
revoke execute on function public.aplicar_saldo_em_nova_parcela()          from public, anon, authenticated;

grant execute on function public.is_admin()                             to authenticated;
grant execute on function public.marcar_senha_trocada()                 to authenticated;
grant execute on function public.aprovar_pagamento(uuid)                to authenticated;  -- valida is_admin() internamente
grant execute on function public.recusar_pagamento(uuid, text, numeric) to authenticated;  -- valida is_admin() internamente


-- =============================================================================
-- 6. ROW LEVEL SECURITY (item 1.2)
-- =============================================================================
-- Sem política = acesso negado. Usuários anônimos (anon) não têm nenhuma política.
-- "(select auth.uid())" é o padrão recomendado pelo Supabase (melhor performance).

alter table public.perfis                 enable row level security;
alter table public.parcelas               enable row level security;
alter table public.pagamentos             enable row level security;
alter table public.alocacoes_pagamento    enable row level security;
alter table public.logs_auditoria         enable row level security;
alter table public.configuracoes_atletica enable row level security;

-- ---------- perfis ----------
create policy "perfis: ver o próprio ou admin vê todos"
  on public.perfis for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

create policy "perfis: admin atualiza"
  on public.perfis for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
-- INSERT: feito pelo trigger handle_new_user. DELETE: não permitido (use ativo=false).

-- ---------- parcelas ----------
create policy "parcelas: aluno vê as próprias, admin vê todas"
  on public.parcelas for select to authenticated
  using (aluno_id = (select auth.uid()) or (select public.is_admin()));

create policy "parcelas: admin cria"
  on public.parcelas for insert to authenticated
  with check ((select public.is_admin()));

create policy "parcelas: admin atualiza"
  on public.parcelas for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "parcelas: admin exclui"
  on public.parcelas for delete to authenticated
  using ((select public.is_admin()));
-- (exclusão falha automaticamente se a parcela já tiver alocações — FK restrict)

-- ---------- pagamentos ----------
create policy "pagamentos: aluno vê os próprios, admin vê todos"
  on public.pagamentos for select to authenticated
  using (aluno_id = (select auth.uid()) or (select public.is_admin()));

create policy "pagamentos: aluno envia o próprio comprovante"
  on public.pagamentos for insert to authenticated
  with check (
    aluno_id = (select auth.uid())
    and status_validacao = 'aguardando'
    and avaliado_por is null
    and data_avaliacao is null
    and motivo_recusa is null
    and arquivo_excluido = false
    and (comprovante_path is null
         or split_part(comprovante_path, '/', 2) = (select auth.uid())::text)
  );

create policy "pagamentos: admin atualiza (ex.: marcar arquivo_excluido)"
  on public.pagamentos for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));
-- Aprovação/recusa devem usar as funções aprovar_pagamento / recusar_pagamento.

-- ---------- alocacoes_pagamento ----------
create policy "alocacoes: aluno vê as das próprias parcelas, admin vê todas"
  on public.alocacoes_pagamento for select to authenticated
  using (
    (select public.is_admin())
    or exists (
      select 1 from public.parcelas p
      where p.id = parcela_id and p.aluno_id = (select auth.uid())
    )
  );
-- Sem INSERT/UPDATE/DELETE: só o motor financeiro (funções SECURITY DEFINER) escreve aqui.

-- ---------- logs_auditoria ----------
create policy "logs: apenas admin lê"
  on public.logs_auditoria for select to authenticated
  using ((select public.is_admin()));
-- Sem políticas de escrita: logs são gravados apenas pelas funções.

-- ---------- configuracoes_atletica ----------
create policy "config: qualquer usuário logado lê (necessário para gerar o PIX)"
  on public.configuracoes_atletica for select to authenticated
  using (true);

create policy "config: admin atualiza"
  on public.configuracoes_atletica for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));


-- =============================================================================
-- 7. STORAGE — bucket privado "comprovantes" (item 1.3)
-- =============================================================================
-- Caminho do arquivo DENTRO do bucket: {ano}-{mes}/{aluno_id}/{pagamento_id}.{ext}
--   ex.: 2026-10/3f2a.../9b1c....webp
--   storage.foldername(name) -> {'2026-10', '<aluno_id>'}  => [2] é o dono.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'comprovantes',
  'comprovantes',
  false,                                   -- privado: acesso só via URL assinada
  512000,                                  -- 500 KB
  array['image/webp', 'application/pdf']
);

create policy "comprovantes: aluno lê os próprios, admin lê todos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'comprovantes'
    and (
      (storage.foldername(name))[2] = (select auth.uid())::text
      or (select public.is_admin())
    )
  );

create policy "comprovantes: aluno envia na própria pasta"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'comprovantes'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );

create policy "comprovantes: apenas admin exclui"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'comprovantes'
    and (select public.is_admin())
  );
-- Sem política de UPDATE: comprovantes não podem ser sobrescritos (integridade da prova).


-- =============================================================================
-- 8. PÓS-INSTALAÇÃO (rodar manualmente depois)
-- =============================================================================
-- 1) Crie seu usuário em Authentication -> Users -> "Add user" (marque Auto Confirm).
-- 2) Promova-o a tesoureiro:
--      update public.perfis
--         set role = 'admin', precisa_trocar_senha = false, nome_completo = 'Seu Nome'
--       where email = 'seu-email@exemplo.com';
-- =============================================================================
