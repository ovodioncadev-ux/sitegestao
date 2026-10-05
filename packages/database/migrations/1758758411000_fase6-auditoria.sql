-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 6 — auditoria.
--
-- Responde a quatro perguntas sobre qualquer registro importante:
--   Quem alterou?   Quando?   O que estava antes?   O que ficou depois?
--
-- Por que gatilho no banco e não uma chamada em cada ação do painel: uma
-- alteração feita por qualquer caminho (tela, função SQL, script de
-- manutenção) deixa rastro. Não depende de alguém lembrar de registrar.
--
-- Quem age: `app.usuario_id` da transação. O painel o envia pelo
-- `comoAdmin({ usuarioId })`; o assinante, pelo `comoUsuario()`. Sem ele, a
-- linha fica com `usuario_id` nulo = "sistema".
-- Por quê: `app.motivo`, gravado pelas funções de pausa, cancelamento etc.
--
-- A tabela é IMUTÁVEL: nenhum papel de aplicação escreve nela (só o gatilho,
-- que é security definer) e um gatilho recusa UPDATE, DELETE e TRUNCATE até
-- para a conexão administrativa. Só quem tem acesso de dono do banco pode
-- desligar esse gatilho de propósito (ex.: limpeza de dados de teste).
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create table auditoria (
  id                bigint generated always as identity primary key,
  criado_em         timestamptz not null default now(),
  usuario_id        text,                       -- nulo = sistema
  acao              text not null,
  entidade          text not null,
  entidade_id       text not null,
  dados_anteriores  jsonb,
  dados_novos       jsonb,
  motivo            text
);

comment on table auditoria is
  'Histórico imutável de alterações. Escrita só por gatilho; leitura só pelo dono.';
comment on column auditoria.usuario_id is
  'Quem agiu (id da conta). Nulo = sistema (ação sem usuário na transação).';

create index auditoria_entidade_idx on auditoria (entidade, entidade_id, id desc);
create index auditoria_criado_idx   on auditoria (criado_em desc);
create index auditoria_usuario_idx  on auditoria (usuario_id);

alter table auditoria enable row level security;

revoke all on table auditoria from app_anon, app_usuario;
grant select on table auditoria to app_usuario;

create policy "auditoria: so o dono le"
  on auditoria for select to app_usuario
  using ((select sou_dono()));

-- Imutabilidade: vale até para a conexão administrativa.
create or replace function auditoria_imutavel()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'A auditoria não pode ser alterada nem apagada.';
end;
$$;

create trigger auditoria_sem_alteracao
  before update or delete on auditoria
  for each row execute function auditoria_imutavel();

create trigger auditoria_sem_truncate
  before truncate on auditoria
  for each statement execute function auditoria_imutavel();

revoke execute on function auditoria_imutavel() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- O gatilho genérico
-- ───────────────────────────────────────────────────────────────────────────
create or replace function auditar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old     jsonb;
  v_new     jsonb;
  v_acao    text;
  v_id      text;
  v_ignorar text[] := array['atualizado_em'];
  v_st_ant  text;
  v_st_nov  text;
  v_st_mudou boolean;
  v_us_ant  text;
  v_us_nov  text;
  v_usuario text := nullif(current_setting('app.usuario_id', true), '');
  v_motivo  text := nullif(current_setting('app.motivo', true), '');
begin
  if tg_op <> 'INSERT' then v_old := to_jsonb(old); end if;
  if tg_op <> 'DELETE' then v_new := to_jsonb(new); end if;
  v_id := coalesce(v_new, v_old) ->> 'id';

  -- Campos que mudam sozinhos, sem ninguém ter decidido nada, não geram linha.
  if tg_table_name = 'assinaturas' then
    v_ignorar := array_append(v_ignorar, 'proxima_entrega');
  end if;

  if tg_op = 'UPDATE' and (v_old - v_ignorar) = (v_new - v_ignorar) then
    return null;
  end if;

  -- Campos lidos pelo jsonb, não por old.x/new.x: o PL/pgSQL analisa a
  -- expressão inteira de uma vez, e `old.usuario_id` quebraria nas tabelas que
  -- não têm essa coluna, mesmo em um ramo que nunca executa.
  v_st_ant := v_old ->> 'status';
  v_st_nov := v_new ->> 'status';
  v_st_mudou := v_st_ant is distinct from v_st_nov;
  v_us_ant := v_old ->> 'usuario_id';
  v_us_nov := v_new ->> 'usuario_id';

  v_acao := case tg_table_name

    when 'clientes' then case
      when tg_op = 'INSERT' then 'cliente_criado'
      when tg_op = 'DELETE' then 'cliente_removido'
      when v_us_ant is distinct from v_us_nov and v_us_nov is not null then 'conta_vinculada'
      when v_us_ant is distinct from v_us_nov then 'conta_desvinculada'
      else 'cliente_alterado'
    end

    when 'assinaturas' then case
      when tg_op = 'INSERT' then 'assinatura_criada'
      when tg_op = 'DELETE' then 'assinatura_removida'
      when v_st_mudou and v_st_nov = 'pausada'   then 'assinatura_pausada'
      when v_st_mudou and v_st_nov = 'cancelada' then 'assinatura_cancelada'
      when v_st_mudou and v_st_nov = 'encerrada' then 'assinatura_encerrada'
      when v_st_mudou and v_st_nov = 'ativa'     then 'assinatura_reativada'
      else 'assinatura_alterada'
    end

    when 'entregas' then case
      when tg_op = 'INSERT' then 'entrega_criada'
      when tg_op = 'DELETE' then 'entrega_removida'
      when v_st_mudou then 'entrega_marcada_' || v_st_nov
      else 'entrega_alterada'
    end

    when 'faturas' then case
      when tg_op = 'INSERT' then 'fatura_criada'
      when tg_op = 'DELETE' then 'fatura_removida'
      when v_st_mudou and v_st_nov = 'paga'      then 'pagamento_registrado'
      when v_st_mudou and v_st_nov = 'cancelada' then 'fatura_cancelada'
      when v_st_mudou and v_st_nov = 'atrasada'  then 'fatura_atrasada'
      else 'fatura_alterada'
    end

    when 'config_negocio' then 'configuracao_alterada'
    when 'planos'         then 'plano_alterado'
    when 'faixas_cep_atendidas' then case tg_op
      when 'INSERT' then 'faixa_criada'
      when 'DELETE' then 'faixa_removida'
      else 'faixa_alterada'
    end

    else tg_table_name || '_' || lower(tg_op)
  end;

  insert into auditoria (usuario_id, acao, entidade, entidade_id, dados_anteriores, dados_novos, motivo)
  values (v_usuario, v_acao, tg_table_name, v_id, v_old, v_new, v_motivo);

  return null;
end;
$$;

comment on function auditar() is
  'Grava em `auditoria` quem, o quê e por quê. Ignora atualizações que só mexem em campos automáticos.';

revoke execute on function auditar() from public;

create trigger clientes_auditoria_tg
  after insert or update or delete on clientes
  for each row execute function auditar();
create trigger assinaturas_auditoria_tg
  after insert or update or delete on assinaturas
  for each row execute function auditar();
create trigger entregas_auditoria_tg
  after insert or update or delete on entregas
  for each row execute function auditar();
create trigger faturas_auditoria_tg
  after insert or update or delete on faturas
  for each row execute function auditar();
create trigger config_negocio_auditoria_tg
  after update on config_negocio
  for each row execute function auditar();
create trigger planos_auditoria_tg
  after insert or update or delete on planos
  for each row execute function auditar();
create trigger faixas_auditoria_tg
  after insert or update or delete on faixas_cep_atendidas
  for each row execute function auditar();


-- Down Migration

drop trigger if exists faixas_auditoria_tg          on faixas_cep_atendidas;
drop trigger if exists planos_auditoria_tg          on planos;
drop trigger if exists config_negocio_auditoria_tg  on config_negocio;
drop trigger if exists faturas_auditoria_tg         on faturas;
drop trigger if exists entregas_auditoria_tg        on entregas;
drop trigger if exists assinaturas_auditoria_tg     on assinaturas;
drop trigger if exists clientes_auditoria_tg        on clientes;
drop function if exists auditar();
drop trigger if exists auditoria_sem_truncate on auditoria;
drop trigger if exists auditoria_sem_alteracao on auditoria;
drop function if exists auditoria_imutavel();
drop policy if exists "auditoria: so o dono le" on auditoria;
drop table if exists auditoria;
