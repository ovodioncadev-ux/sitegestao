-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 3 — conteúdo público do site.
--
--   pnpm --filter @ovo/database teste:bloco3
--
-- Cobre: planos_publicos() com entregas por mês, FAQ (anon lê só as ativas,
-- ninguém escreve pelo app, dono altera e fica na auditoria), site_conteudo()
-- e limitar_acesso_publico(). Tudo dentro de uma transação com ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_int     int;
  v_txt     text;
  v_bool    boolean;
  v_row     record;
  v_ok      boolean;
  id_dono   text := 'teste-b3-dono';
  id_user   text := 'teste-b3-user';
  faq_ativa bigint;
  faq_off   bigint;
begin
  insert into "user" (id, name, email) values (id_dono, 'Dono B3', 'dono-b3@exemplo.test');
  insert into "user" (id, name, email) values (id_user, 'Assinante B3', 'user-b3@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  update config_negocio set preco_pente_centavos = 4100;

  raise notice '═══ Bloco 3: vitrine e conteúdo público ═══';

  -- B3.1 ── planos_publicos: preço da entrega e entregas por mês ─────────────
  v_total := v_total + 1;
  set local role app_anon;
  select count(*) into v_int from planos_publicos();
  select preco_entrega_centavos, entregas_por_mes, preco_centavos into v_row
    from planos_publicos() where frequencia = 'semanal';
  reset role;
  if v_int = 3 and v_row.preco_entrega_centavos = 4100 and v_row.entregas_por_mes = 4
     and v_row.preco_centavos = 16400 then
    raise notice '  OK    B3.1  anon vê 3 planos; semanal = R$ 41 por entrega × 4 = R$ 164 (derivado do banco)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.1  planos_publicos: % planos, entrega %, entregas %, mensal %',
      v_int, v_row.preco_entrega_centavos, v_row.entregas_por_mes, v_row.preco_centavos;
  end if;

  -- B3.2 ── mudar o preço do pente muda a vitrine, sem código ────────────────
  v_total := v_total + 1;
  update config_negocio set preco_pente_centavos = 5000;
  select preco_entrega_centavos, preco_centavos into v_row from planos_publicos() where frequencia = 'quinzenal';
  update config_negocio set preco_pente_centavos = 4100;
  if v_row.preco_entrega_centavos = 5000 and v_row.preco_centavos = 10000 then
    raise notice '  OK    B3.2  preço do pente em R$ 50: quinzenal = R$ 50 por entrega, R$ 100/mês';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.2  vitrine não seguiu a configuração (% / %)', v_row.preco_entrega_centavos, v_row.preco_centavos;
  end if;

  -- B3.3 ── FAQ: anon lê só as ativas ─────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_dono, true);
  insert into faq_itens (pergunta, resposta, ordem, ativo) values ('Pergunta ativa B3?', 'Resposta ativa B3.', 900, true)
    returning id into faq_ativa;
  insert into faq_itens (pergunta, resposta, ordem, ativo) values ('Pergunta oculta B3?', 'Resposta oculta B3.', 901, false)
    returning id into faq_off;
  set local role app_anon;
  select count(*) into v_int from faq_itens where id in (faq_ativa, faq_off);
  select count(*) into v_int from faq_itens where id = faq_off;
  v_bool := v_int = 0;
  select count(*) into v_int from faq_itens where id = faq_ativa;
  reset role;
  if v_bool and v_int = 1 then
    raise notice '  OK    B3.3  anon lê a pergunta ativa e NÃO vê a oculta';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.3  RLS do FAQ (oculta visível: %, ativa visível: %)', not v_bool, v_int;
  end if;

  -- B3.4 ── anon e assinante não escrevem no FAQ ─────────────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin
    set local role app_anon;
    insert into faq_itens (pergunta, resposta) values ('Invasão anon?', 'Não deveria entrar.');
    v_ok := false;
  exception when insufficient_privilege then null;
  end;
  reset role;
  begin
    perform set_config('app.usuario_id', id_user, true);
    set local role app_usuario;
    update faq_itens set resposta = 'Alterada pelo assinante.' where id = faq_ativa;
    get diagnostics v_int = row_count;
    delete from faq_itens where id = faq_ativa;
    v_ok := false;
  exception when insufficient_privilege then null;
  end;
  reset role;
  perform set_config('app.usuario_id', id_dono, true);
  if v_ok then
    raise notice '  OK    B3.4  anon e assinante sem INSERT/UPDATE/DELETE no FAQ (privilégio negado)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.4  um papel de aplicação conseguiu escrever no FAQ';
  end if;

  -- B3.5 ── constraints: texto vazio e curto demais são recusados ────────────
  v_total := v_total + 1;
  v_ok := true;
  begin
    insert into faq_itens (pergunta, resposta) values ('?', 'Resposta válida o bastante.');
    v_ok := false;
  exception when check_violation then null;
  end;
  begin
    insert into faq_itens (pergunta, resposta) values ('Pergunta válida?', repeat('x', 1001));
    v_ok := false;
  exception when check_violation then null;
  end;
  if v_ok then
    raise notice '  OK    B3.5  pergunta curta demais e resposta acima de 1000 caracteres são recusadas';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.5  constraint de tamanho do FAQ não barrou';
  end if;

  -- B3.6 ── alteração do dono entra na auditoria ─────────────────────────────
  v_total := v_total + 1;
  update faq_itens set resposta = 'Resposta ativa B3 revisada.' where id = faq_ativa;
  select count(*) into v_int from auditoria
   where entidade = 'faq_itens' and entidade_id = faq_ativa::text and usuario_id = id_dono;
  if v_int >= 2 then
    raise notice '  OK    B3.6  criação e edição do FAQ na auditoria, com quem agiu (% linhas)', v_int;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.6  auditoria do FAQ: % linhas', v_int;
  end if;

  -- B3.7 ── site_conteudo: derivado dos planos e da configuração ─────────────
  v_total := v_total + 1;
  set local role app_anon;
  select * into v_row from site_conteudo();
  reset role;
  if v_row.freshness_max_dias = 7 and v_row.frete_gratis and v_row.desconto_primeiro_mes_pct = 10
     and v_row.dia_corte = 1 and v_row.hora_corte = '18:00' then
    raise notice '  OK    B3.7  site_conteudo: frescor 7 dias, frete grátis, 10%% no 1º mês, corte segunda 18:00';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.7  site_conteudo devolveu % / % / % / % / %',
      v_row.freshness_max_dias, v_row.frete_gratis, v_row.desconto_primeiro_mes_pct, v_row.dia_corte, v_row.hora_corte;
  end if;

  -- B3.8 ── frete em um plano deixa de ser "grátis em todos" ─────────────────
  v_total := v_total + 1;
  update planos set frete_centavos = 100 where frequencia = 'mensal';
  select frete_gratis into v_bool from site_conteudo();
  update planos set frete_centavos = 0 where frequencia = 'mensal';
  if v_bool = false then
    raise notice '  OK    B3.8  com frete em um plano, o site deixa de afirmar "frete grátis" em todos';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.8  site_conteudo continuou dizendo frete grátis em todos';
  end if;

  -- B3.9 ── limitar_acesso_publico: libera até o limite e bloqueia depois ────
  v_total := v_total + 1;
  set local role app_anon;
  v_ok := true;
  for i in 1..30 loop
    if limitar_acesso_publico('203.0.113.7', 'area') then v_ok := false; end if;
  end loop;
  v_bool := limitar_acesso_publico('203.0.113.7', 'area');          -- 31ª
  select limitar_acesso_publico('203.0.113.8', 'area') into v_txt;  -- outro IP: livre
  reset role;
  if v_ok and v_bool and v_txt = 'false' then
    raise notice '  OK    B3.9  30 consultas por minuto passam; a 31ª do mesmo IP é bloqueada; outro IP segue livre';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.9  limite (até 30 livres: %, 31ª bloqueada: %, outro IP: %)', v_ok, v_bool, v_txt;
  end if;

  -- B3.10 ─ rota fora da lista é recusada; app_anon continua sem escrita ──────
  v_total := v_total + 1;
  v_ok := true;
  begin
    set local role app_anon;
    perform limitar_acesso_publico('203.0.113.9', 'qualquer');
    v_ok := false;
  exception when raise_exception then null;
  end;
  reset role;
  begin
    set local role app_anon;
    insert into rateLimit (ip, endpoint, reset_at) values ('x', 'y', now() + interval '1 minute');
    v_ok := false;
  exception when insufficient_privilege then null;
  end;
  reset role;
  if v_ok then
    raise notice '  OK    B3.10 rota fora da lista é recusada e o app_anon não escreve direto em rateLimit';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B3.10 rota arbitrária aceita ou escrita direta permitida';
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 3: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 3 passaram.', v_total;
end;
$$;

rollback;
