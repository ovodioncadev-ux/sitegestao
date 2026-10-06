-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 5 — captação de interesse de quem está fora da área de entrega.
--
-- Quem digita um CEP não atendido pode deixar telefone ou e-mail para ser
-- avisado quando a região entrar. Dado pessoal, então:
--   · consentimento explícito, com a VERSÃO do texto aceito gravada;
--   · escrita só por registrar_interesse() (validação e lista fechada);
--   · só o dono lê; o dono pode remover (pedido de exclusão do titular);
--   · SEM gatilho de auditoria: a auditoria é imutável e copiaria telefone e
--     e-mail para um lugar de onde não dá para apagar (LGPD).
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create table interessados (
  id                    bigint generated always as identity primary key,
  nome                  text check (nome is null or char_length(nome) between 2 and 120),
  telefone              text check (telefone is null or telefone ~ '^\d{10,11}$'),
  email                 text check (email is null or (char_length(email) <= 254 and email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$')),
  cep                   text not null check (cep ~ '^\d{8}$'),
  origem                text not null check (origem in ('site', 'assinar')),
  consentimento_versao  smallint not null check (consentimento_versao >= 1),
  consentimento_em      timestamptz not null default now(),
  status                text not null default 'novo' check (status in ('novo', 'avisado', 'descartado')),
  area_atendida_em      timestamptz,
  avisado_em            timestamptz,
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now(),
  constraint interessados_tem_contato check (telefone is not null or email is not null)
);

-- A mesma pessoa pedindo de novo não cria linha nova (e o site responde igual).
create unique index interessados_unico_idx
  on interessados (cep, (coalesce(telefone, '')), (coalesce(email, '')));
create index interessados_status_idx on interessados (status, criado_em);

comment on table interessados is
  'Quem pediu aviso para um CEP ainda não atendido. Dado pessoal com consentimento versionado; sem auditoria de propósito (a auditoria é imutável).';
comment on column interessados.consentimento_versao is
  'Versão do texto de consentimento aceito (packages/config/src/privacidade.mjs).';
comment on column interessados.area_atendida_em is
  'Quando uma faixa de CEP ativa passou a cobrir este CEP: o dono já pode avisar.';

alter table interessados enable row level security;

revoke all on table interessados from app_anon, app_usuario;
grant select on table interessados to app_usuario;

create policy "interessados: so o dono le"
  on interessados for select to app_usuario
  using ((select sou_dono()));

-- Nenhuma policy de insert, update ou delete: escrita pública só por
-- registrar_interesse(); o dono escreve pela conexão administrativa.

create function registrar_interesse(
  p_nome                 text,
  p_telefone             text,
  p_email                text,
  p_cep                  text,
  p_origem               text,
  p_consentimento_versao integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nome     text := nullif(btrim(p_nome), '');
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_email    text := nullif(lower(btrim(p_email)), '');
  v_cep      text := regexp_replace(coalesce(p_cep, ''), '\D', '', 'g');
begin
  if p_consentimento_versao is null or p_consentimento_versao < 1 then
    raise exception 'É preciso aceitar o uso do contato para avisar sobre a entrega.';
  end if;
  if p_origem is null or p_origem not in ('site', 'assinar') then
    raise exception 'Origem desconhecida.';
  end if;
  if v_cep !~ '^\d{8}$' then
    raise exception 'CEP precisa ter 8 dígitos.';
  end if;

  if length(v_telefone) in (12, 13) and v_telefone like '55%' then
    v_telefone := substr(v_telefone, 3);
  end if;
  if v_telefone = '' then
    v_telefone := null;
  elsif v_telefone !~ '^\d{10,11}$' then
    raise exception 'Telefone precisa ter 10 ou 11 dígitos (com DDD).';
  end if;

  if v_email is not null and (char_length(v_email) > 254 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'E-mail inválido.';
  end if;
  if v_nome is not null and char_length(v_nome) not between 2 and 120 then
    raise exception 'Nome precisa ter entre 2 e 120 caracteres.';
  end if;
  if v_telefone is null and v_email is null then
    raise exception 'Informe um telefone ou um e-mail para receber o aviso.';
  end if;

  -- CEP já atendido: não há o que avisar. Resposta igual à de sucesso (nada a vazar).
  if cep_dentro_area_entrega(v_cep) then
    return;
  end if;

  insert into interessados (nome, telefone, email, cep, origem, consentimento_versao)
  values (v_nome, v_telefone, v_email, v_cep, p_origem, p_consentimento_versao)
  on conflict (cep, (coalesce(telefone, '')), (coalesce(email, ''))) do nothing;
end;
$$;

comment on function registrar_interesse(text, text, text, text, text, integer) is
  'Registra o pedido de aviso de quem está fora da área. Valida tudo, exige consentimento (versão do texto) e não grava duplicata. Resposta igual para novo, repetido e CEP já atendido.';

revoke execute on function registrar_interesse(text, text, text, text, text, integer) from public;
grant  execute on function registrar_interesse(text, text, text, text, text, integer) to app_anon, app_usuario;

-- Quando uma faixa ativa passa a cobrir o CEP de quem esperava, marca "pronto para avisar".
create function marcar_interessados_com_area()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.ativo then
    update interessados
       set area_atendida_em = now(), atualizado_em = now()
     where status = 'novo'
       and area_atendida_em is null
       and cep between new.cep_inicio and new.cep_fim;
  end if;
  return null;
end;
$$;

revoke execute on function marcar_interessados_com_area() from public;

create trigger faixas_marcam_interessados_tg
  after insert or update on faixas_cep_atendidas
  for each row execute function marcar_interessados_com_area();

-- Limite da rota pública de interesse: poucos pedidos por minuto por IP.
create or replace function limitar_acesso_publico(p_ip text, p_rota text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip     text := coalesce(nullif(left(btrim(p_ip), 64), ''), 'desconhecido');
  v_limite integer;
begin
  v_limite := case p_rota
    when 'area'      then 30   -- /api/area: uma ida ao banco por consulta
    when 'evento'    then 60   -- /api/evento: contagem do funil
    when 'interesse' then 5    -- /api/interesse: grava dado pessoal
    else null
  end;
  if v_limite is null then
    raise exception 'Rota pública desconhecida.';
  end if;

  return verificar_rate_limit(v_ip, 'publico:' || p_rota, v_limite, 60);
end;
$$;


-- Down Migration

create or replace function limitar_acesso_publico(p_ip text, p_rota text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ip     text := coalesce(nullif(left(btrim(p_ip), 64), ''), 'desconhecido');
  v_limite integer;
begin
  v_limite := case p_rota
    when 'area'   then 30
    when 'evento' then 60
    else null
  end;
  if v_limite is null then
    raise exception 'Rota pública desconhecida.';
  end if;

  return verificar_rate_limit(v_ip, 'publico:' || p_rota, v_limite, 60);
end;
$$;

drop trigger if exists faixas_marcam_interessados_tg on faixas_cep_atendidas;
drop function if exists marcar_interessados_com_area();
drop function if exists registrar_interesse(text, text, text, text, text, integer);
drop table if exists interessados;
