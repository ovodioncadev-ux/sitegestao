-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 4 — funil de conversão do site.
--
-- Conta quantas pessoas chegam a cada etapa (plano clicado → conta criada →
-- endereço salvo → assinatura confirmada). Nenhum dado pessoal: a linha guarda
-- só a etapa, o plano (público) e o instante. Sem IP, sem cookie, sem id de
-- sessão — por isso também não dá para ligar etapas da mesma pessoa; o funil
-- é de contagem por etapa, não de rastreio.
--
-- Escrita só por registrar_evento_funil() (lista fechada de etapas). O dono lê.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create table eventos_funil (
  id        bigint generated always as identity primary key,
  etapa     text        not null
            check (etapa in ('plano_clicado', 'conta_criada', 'endereco_salvo', 'assinatura_confirmada')),
  plano     frequencia_plano,
  criado_em timestamptz not null default now()
);

create index eventos_funil_criado_em_idx on eventos_funil (criado_em);

comment on table eventos_funil is
  'Contagem anônima das etapas do funil de assinatura. Sem dado pessoal. Escrita só por registrar_evento_funil().';

alter table eventos_funil enable row level security;

revoke all on table eventos_funil from app_anon, app_usuario;
grant select on table eventos_funil to app_usuario;

create policy "funil: so o dono le"
  on eventos_funil for select to app_usuario
  using ((select sou_dono()));

-- Nenhuma policy de insert, update ou delete.

create function registrar_evento_funil(p_etapa text, p_plano text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plano frequencia_plano;
begin
  if p_etapa is null or p_etapa not in ('plano_clicado', 'conta_criada', 'endereco_salvo', 'assinatura_confirmada') then
    raise exception 'Etapa desconhecida.';
  end if;

  if p_plano is not null then
    begin
      v_plano := p_plano::frequencia_plano;
    exception when invalid_text_representation then
      raise exception 'Plano desconhecido.';
    end;
  end if;

  insert into eventos_funil (etapa, plano) values (p_etapa, v_plano);
end;
$$;

comment on function registrar_evento_funil(text, text) is
  'Registra uma etapa do funil (lista fechada) e o plano público. Não recebe nem grava dado pessoal.';

revoke execute on function registrar_evento_funil(text, text) from public;
grant  execute on function registrar_evento_funil(text, text) to app_anon, app_usuario;

-- A rota pública de eventos também tem limite por IP.
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
    when 'area'   then 30   -- /api/area: uma ida ao banco por consulta
    when 'evento' then 60   -- /api/evento: contagem do funil
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
    when 'area' then 30
    else null
  end;
  if v_limite is null then
    raise exception 'Rota pública desconhecida.';
  end if;

  return verificar_rate_limit(v_ip, 'publico:' || p_rota, v_limite, 60);
end;
$$;

drop function if exists registrar_evento_funil(text, text);
drop table if exists eventos_funil;
