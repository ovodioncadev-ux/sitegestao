-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 3 — conteúdo público do site vindo do banco.
--
--   1. planos_publicos() passa a devolver entregas_por_mes e o preço da entrega
--      (D10: o site mostra "R$ 41 por entrega", não um mensal fixo).
--   2. faq_itens: perguntas frequentes editáveis pelo dono (anon só lê as ativas).
--   3. site_conteudo(): regras de exibição derivadas dos planos e da configuração
--      (frescor, frete, desconto, corte), sem tabela exposta.
--   4. rateLimit com RLS (correção da Fase 10) e limitar_acesso_publico(): contador por IP para rotas públicas SEM cache,
--      reaproveitando a tabela rateLimit (Fase 10), sem dar escrita ao app_anon.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Vitrine de planos com entregas por mês
-- ───────────────────────────────────────────────────────────────────────────
drop function if exists planos_publicos();

create function planos_publicos()
returns table (
  id                        smallint,
  frequencia                text,
  nome                      text,
  intervalo_dias            smallint,
  ancorar_em_quarta         boolean,
  preco_centavos            integer,
  freshness_max_dias        smallint,
  frete_centavos            integer,
  desconto_primeiro_mes_pct numeric,
  selo                      text,
  entregas_por_mes          smallint,
  preco_entrega_centavos    integer
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.frequencia::text, p.nome, p.intervalo_dias, p.ancorar_em_quarta,
         (c.preco_pente_centavos * p.entregas_por_mes)::integer,
         p.freshness_max_dias, p.frete_centavos, p.desconto_primeiro_mes_pct,
         p.selo, p.entregas_por_mes, c.preco_pente_centavos
    from planos p
    cross join config_negocio c
   where p.ativo and c.id = 1
   order by p.intervalo_dias;
$$;

comment on function planos_publicos() is
  'Vitrine de planos para quem não está logado. preco_centavos = preço do pente × entregas por mês (1 pente por entrega); preco_entrega_centavos = preço de uma entrega. Sem preço no código.';

revoke execute on function planos_publicos() from public;
grant  execute on function planos_publicos() to app_anon, app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. FAQ editável
-- ───────────────────────────────────────────────────────────────────────────
create table faq_itens (
  id            bigint generated always as identity primary key,
  pergunta      text        not null check (char_length(pergunta) between 5 and 200),
  resposta      text        not null check (char_length(resposta) between 5 and 1000),
  ordem         integer     not null default 0,
  ativo         boolean     not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

comment on table faq_itens is
  'Perguntas frequentes do site. Texto público; o telefone do WhatsApp NÃO entra aqui (fonte única: packages/config/src/whatsapp.mjs).';

alter table faq_itens enable row level security;

revoke all on table faq_itens from app_anon, app_usuario;
grant select on table faq_itens to app_anon, app_usuario;

create policy "faq: anonimo le as ativas"
  on faq_itens for select to app_anon
  using (ativo);

create policy "faq: usuario logado le ativas ou todas se for dono"
  on faq_itens for select to app_usuario
  using (ativo or (select sou_dono()));

-- Nenhuma policy de insert, update ou delete: escrita só pela conexão
-- administrativa, depois de exigirDono() aprovar.

create trigger faq_itens_auditoria_tg
  after insert or update or delete on faq_itens
  for each row execute function auditar();

insert into faq_itens (pergunta, resposta, ordem) values
  ('Como assino?',
   'Escolha o plano, crie sua conta, informe o endereço (o CEP mostra se já entregamos aí) e confirme a assinatura. Tudo pelo site.', 10),
  ('Qual é o prazo de frescor dos ovos?',
   'No máximo 7 dias entre a colheita na fazenda e a entrega na sua casa, em todos os planos.', 20),
  ('O frete é cobrado?',
   'Não, o frete é grátis para todos os planos dentro da área atendida.', 30),
  ('O desconto do 1º mês vale para qualquer forma de pagamento?',
   'Sim, os 10% de desconto no primeiro mês valem tanto para cartão quanto para PIX.', 40),
  ('Como funciona o pagamento?',
   'Hoje a confirmação é manual: você envia o comprovante do PIX (ou combina o cartão) pelo WhatsApp e a Ovo di Onça confirma o pedido.', 50),
  ('Meu bairro é atendido?',
   'Digite seu CEP na seção Área de entrega. Fora da área atendida ainda não conseguimos entregar.', 60);


-- ───────────────────────────────────────────────────────────────────────────
-- 3. Regras de exibição derivadas do banco
-- ───────────────────────────────────────────────────────────────────────────
create function site_conteudo()
returns table (
  freshness_max_dias        smallint,
  frete_gratis              boolean,
  desconto_primeiro_mes_pct numeric,
  dia_corte                 smallint,
  hora_corte                text
)
language sql
stable
security definer
set search_path = public
as $$
  select max(p.freshness_max_dias),
         coalesce(bool_and(p.frete_centavos = 0), false),
         max(p.desconto_primeiro_mes_pct),
         max(c.dia_corte),
         to_char(max(c.hora_corte), 'HH24:MI')
    from planos p
    cross join config_negocio c
   where p.ativo and c.id = 1;
$$;

comment on function site_conteudo() is
  'Texto de vitrine derivado dos planos ativos e da configuração: frescor máximo, frete grátis em todos?, maior desconto do 1º mês e o corte de pedidos. Sem plano ativo devolve nulos.';

revoke execute on function site_conteudo() from public;
grant  execute on function site_conteudo() to app_anon, app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 4. Limite de acesso a rotas públicas sem cache
--
-- Correção da Fase 10: rateLimit nasceu sem RLS (o teste estrutural da Lei 1
-- reprova "tabela sem RLS"). Nenhum papel de aplicação tem privilégio nela e
-- nenhuma policy é criada: só o dono (funções security definer) lê e escreve.
alter table rateLimit enable row level security;

-- verificar_rate_limit() é security invoker e app_usuario não tem privilégio na
-- tabela: o grant da Fase 10 nunca funcionou para esse papel e só a deixava
-- alcançável por acidente. As rotas públicas passam por limitar_acesso_publico().
revoke execute on function verificar_rate_limit(text, text, integer, integer) from app_usuario;

-- Lista fechada de rotas e de limites: o chamador não escolhe o limite.
-- Roda como dono da tabela (security definer), então o app_anon continua sem
-- nenhum privilégio de escrita em rateLimit.
-- ───────────────────────────────────────────────────────────────────────────
create function limitar_acesso_publico(p_ip text, p_rota text)
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
    when 'area' then 30   -- /api/area: uma ida ao banco por consulta
    else null
  end;
  if v_limite is null then
    raise exception 'Rota pública desconhecida.';
  end if;

  return verificar_rate_limit(v_ip, 'publico:' || p_rota, v_limite, 60);
end;
$$;

comment on function limitar_acesso_publico(text, text) is
  'TRUE = bloqueado. Conta requisições por IP e rota pública numa janela de 60 s (limites fixos no corpo da função).';

revoke execute on function limitar_acesso_publico(text, text) from public;
grant  execute on function limitar_acesso_publico(text, text) to app_anon, app_usuario;


-- Down Migration

grant execute on function verificar_rate_limit(text, text, integer, integer) to app_usuario;
alter table rateLimit disable row level security;
drop function if exists limitar_acesso_publico(text, text);
drop function if exists site_conteudo();
drop trigger if exists faq_itens_auditoria_tg on faq_itens;
drop table if exists faq_itens;

drop function if exists planos_publicos();

create function planos_publicos()
returns table (
  id                        smallint,
  frequencia                text,
  nome                      text,
  intervalo_dias            smallint,
  ancorar_em_quarta         boolean,
  preco_centavos            integer,
  freshness_max_dias        smallint,
  frete_centavos            integer,
  desconto_primeiro_mes_pct numeric,
  selo                      text
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.frequencia::text, p.nome, p.intervalo_dias, p.ancorar_em_quarta,
         (c.preco_pente_centavos * p.entregas_por_mes)::integer,
         p.freshness_max_dias, p.frete_centavos, p.desconto_primeiro_mes_pct,
         p.selo
    from planos p
    cross join config_negocio c
   where p.ativo and c.id = 1
   order by p.intervalo_dias;
$$;

revoke execute on function planos_publicos() from public;
grant  execute on function planos_publicos() to app_anon, app_usuario;
