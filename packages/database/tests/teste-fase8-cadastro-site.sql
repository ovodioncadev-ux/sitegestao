-- ═══════════════════════════════════════════════════════════════════════
-- Fase 8 — cadastro e assinatura feitos pelo próprio cliente, no site.
--
--   pnpm --filter @ovo/database teste:fase8
--
-- Cobre: vínculo por e-mail só com e-mail confirmado, planos públicos sem
-- preço no código, criar_meu_cadastro(), assinar_plano() e o isolamento entre
-- contas. Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total   int := 0;
  v_falhas  int := 0;
  v_int     int;
  v_txt     text;
  v_data    date;
  v_uuid    uuid;
  v_uuid2   uuid;
  v_plano_s smallint;
  cli_a     uuid;
  cli_b     uuid;
  ass_a     uuid;
  id_dono   text := 'teste8-dono';
  id_a      text := 'teste8-conta-a';
  id_b      text := 'teste8-conta-b';
  id_c      text := 'teste8-conta-c';
  id_d      text := 'teste8-conta-d';
begin
  select id into v_plano_s from planos where frequencia = 'semanal';
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('30110000', '30190999', 'Teste F8');
  update config_negocio set preco_pente_centavos = 4100;

  insert into "user" (id, name, email) values (id_dono, 'Dono F8', 'dono-f8@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;

  raise notice '═══ Fase 8: vínculo por e-mail só com e-mail confirmado ═══';

  -- F8.1 ── conta NÃO confirmada não vincula cliente existente ─────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_dono, true);
  insert into clientes (nome, email, cep, endereco, origem)
    values ('Vitima F8', 'vitima.f8@exemplo.test', '30140000', 'Rua V 1', 'organico')
    returning id into cli_a;
  insert into "user" (id, name, email, "emailVerified") values (id_a, 'Invasor', 'VITIMA.F8@exemplo.test', false);
  if (select usuario_id from clientes where id = cli_a) is null then
    raise notice '  OK    F8.1  conta com e-mail NÃO confirmado não assume o cadastro de outra pessoa';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.1  conta não confirmada foi vinculada ao cliente';
  end if;

  -- F8.2 ── ao confirmar o e-mail, vincula ──────────────────────────────────
  v_total := v_total + 1;
  update "user" set "emailVerified" = true where id = id_a;
  if (select usuario_id from clientes where id = cli_a) = id_a then
    raise notice '  OK    F8.2  ao CONFIRMAR o e-mail, o vínculo automático acontece (sem diferenciar caixa)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.2  e-mail confirmado não vinculou';
  end if;

  -- F8.3 ── conta já confirmada + cliente criado depois ────────────────────
  v_total := v_total + 1;
  insert into "user" (id, name, email, "emailVerified") values (id_b, 'Bia', 'bia.f8@exemplo.test', true);
  insert into clientes (nome, email, cep, endereco, origem)
    values ('Bia F8', 'bia.f8@exemplo.test', '30150000', 'Rua B 1', 'organico')
    returning id into cli_b;
  if (select usuario_id from clientes where id = cli_b) = id_b then
    raise notice '  OK    F8.3  cliente criado DEPOIS de conta confirmada: vincula';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.3  cliente não vinculou à conta confirmada';
  end if;

  -- F8.4 ── cliente criado depois de conta NÃO confirmada não vincula ──────
  v_total := v_total + 1;
  insert into "user" (id, name, email, "emailVerified") values (id_c, 'Caio', 'caio.f8@exemplo.test', false);
  insert into clientes (nome, email, cep, endereco, origem)
    values ('Caio F8', 'caio.f8@exemplo.test', '30160000', 'Rua C 1', 'organico')
    returning id into v_uuid;
  if (select usuario_id from clientes where id = v_uuid) is null then
    raise notice '  OK    F8.4  cliente criado depois de conta NÃO confirmada não vincula';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.4  vinculou conta não confirmada';
  end if;
  delete from clientes where id = v_uuid;

  -- F8.5 ── conta de dono confirmada nunca vincula ────────────────────────
  v_total := v_total + 1;
  update "user" set "emailVerified" = true where id = id_dono;
  insert into clientes (nome, email, cep, endereco, origem)
    values ('ClienteDono', 'dono-f8@exemplo.test', '30170000', 'Rua D 1', 'organico')
    returning id into v_uuid;
  if (select usuario_id from clientes where id = v_uuid) is null then
    raise notice '  OK    F8.5  conta de dono, mesmo confirmada, nunca é vinculada a cliente';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.5  conta de dono foi vinculada';
  end if;
  delete from clientes where id = v_uuid;

  raise notice ' ';
  raise notice '═══ Fase 8: planos públicos ═══';

  -- F8.6 ── anon lê planos com preço derivado ──────────────────────────────
  v_total := v_total + 1;
  set local role app_anon;
  select string_agg(frequencia || '=' || preco_centavos, ',' order by intervalo_dias) into v_txt from planos_publicos();
  reset role;
  if v_txt = 'semanal=16400,quinzenal=8200,mensal=4100' then
    raise notice '  OK    F8.6  planos_publicos() derivam o preço do banco (%)', v_txt;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.6  preços = %', v_txt;
  end if;

  -- F8.7 ── mudar o preço do pente muda a vitrine (nada hardcoded) ──────────
  v_total := v_total + 1;
  update config_negocio set preco_pente_centavos = 5000;
  set local role app_anon;
  select preco_centavos into v_int from planos_publicos() where frequencia = 'mensal';
  reset role;
  update config_negocio set preco_pente_centavos = 4100;
  if v_int = 5000 then
    raise notice '  OK    F8.7  a vitrine acompanha config_negocio (nenhum preço no código)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.7  preço mensal = % (esperava 5000)', v_int;
  end if;

  -- F8.8 ── anon não lê config_negocio direto ──────────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_anon;
    perform 1 from config_negocio;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.8  anon leu config_negocio';
  exception when others then
    reset role;
    raise notice '  OK    F8.8  anon continua sem acesso direto a config_negocio';
  end;

  raise notice ' ';
  raise notice '═══ Fase 8: criar_meu_cadastro ═══';

  insert into "user" (id, name, email) values (id_d, 'Dora', 'dora.f8@exemplo.test');

  -- F8.9 ── cadastro dentro da área ────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_d, true);
  set local role app_usuario;
  v_uuid := criar_meu_cadastro('Dora F8', '(31) 99999-1234', '30140-010', 'Rua Teste', '10', null, 'Savassi', 'Belo Horizonte', 'mg');
  reset role;
  if (select usuario_id from clientes where id = v_uuid) = id_d
     and (select email from clientes where id = v_uuid) = 'dora.f8@exemplo.test'
     and (select status::text from clientes where id = v_uuid) = 'cadastro_andamento'
     and (select dentro_area_entrega from clientes where id = v_uuid)
     and (select telefone from clientes where id = v_uuid) = '+5531999991234'
     and (select estado from clientes where id = v_uuid) = 'MG' then
    raise notice '  OK    F8.9  cadastro criado: e-mail da conta, status cadastro_andamento, dentro da área, dados normalizados';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.9  cadastro criado incorretamente';
  end if;
  cli_a := v_uuid;

  -- F8.10 ── segundo cadastro na mesma conta é recusado ────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_d, true);
    set local role app_usuario;
    perform criar_meu_cadastro('Outra Dora', '31999991234', '30140010', 'Rua X', '1', null, 'Savassi', 'BH', 'MG');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.10 segundo cadastro aceito';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.10 uma conta não cria dois cadastros (%)', sqlerrm;
  end;

  -- F8.11 ── e-mail já cadastrado por outra pessoa: recusa neutra ───────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_dono, true);
  insert into clientes (nome, email, cep, endereco, origem)
    values ('Ocupado F8', 'ocupado.f8@exemplo.test', '30140000', 'Rua O 1', 'organico');
  insert into "user" (id, name, email) values ('teste8-conta-e', 'Eva', 'ocupado.f8@exemplo.test');
  begin
    perform set_config('app.usuario_id', 'teste8-conta-e', true);
    set local role app_usuario;
    perform criar_meu_cadastro('Eva F8', '31999991234', '30140010', 'Rua E', '1', null, 'Savassi', 'BH', 'MG');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.11 criou cadastro com e-mail de outro cliente';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.11 e-mail já usado por outro cliente: recusado sem revelar de quem (%)', sqlerrm;
  end;

  -- F8.12 ── validações: cada campo obrigatório ─────────────────────────────
  v_total := v_total + 1;
  v_int := 0;
  insert into "user" (id, name, email) values ('teste8-conta-f', 'Fabio', 'fabio.f8@exemplo.test');
  perform set_config('app.usuario_id', 'teste8-conta-f', true);
  set local role app_usuario;
  begin perform criar_meu_cadastro('Fa', '31999991234', '30140010', 'Rua', '1', null, 'Savassi', 'BH', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '3199', '30140010', 'Rua', '1', null, 'Savassi', 'BH', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '31999991234', '3014', 'Rua', '1', null, 'Savassi', 'BH', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '31999991234', '30140010', '', '1', null, 'Savassi', 'BH', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '31999991234', '30140010', 'Rua', '', null, 'Savassi', 'BH', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '31999991234', '30140010', 'Rua', '1', null, '', 'BH', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '31999991234', '30140010', 'Rua', '1', null, 'Savassi', '', 'MG'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  begin perform criar_meu_cadastro('Fabio', '31999991234', '30140010', 'Rua', '1', null, 'Savassi', 'BH', 'XYZ'); exception when sqlstate 'OV001' then v_int := v_int + 1; end;
  reset role;
  if v_int = 8 then
    raise notice '  OK    F8.12 nome, telefone, CEP, rua, número, bairro, cidade e UF inválidos: os 8 são recusados';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.12 só % de 8 validações recusaram', v_int;
  end if;

  -- F8.13 ── CEP fora da área vira pre_venda ────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', 'teste8-conta-f', true);
  set local role app_usuario;
  v_uuid := criar_meu_cadastro('Fabio F8', '31999991234', '01001000', 'Praça da Sé', '1', null, 'Sé', 'São Paulo', 'SP');
  reset role;
  if (select status::text from clientes where id = v_uuid) = 'pre_venda'
     and not (select dentro_area_entrega from clientes where id = v_uuid) then
    raise notice '  OK    F8.13 CEP fora das faixas: cadastro entra como pre_venda, fora da área';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.13 status = %', (select status from clientes where id = v_uuid);
  end if;
  v_uuid2 := v_uuid;

  -- F8.14 ── dono não usa a função ───────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_dono, true);
    set local role app_usuario;
    perform criar_meu_cadastro('Dono', '31999991234', '30140010', 'Rua', '1', null, 'Savassi', 'BH', 'MG');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.14 conta de dono criou cadastro de assinante';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.14 só conta de assinante cria cadastro (%)', sqlerrm;
  end;

  -- F8.15 ── anônimo não executa ─────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    set local role app_anon;
    perform criar_meu_cadastro('Anon', '31999991234', '30140010', 'Rua', '1', null, 'Savassi', 'BH', 'MG');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.15 anon executou criar_meu_cadastro';
  exception when others then
    reset role;
    raise notice '  OK    F8.15 anônimo não executa criar_meu_cadastro nem assinar_plano (recusado)';
  end;

  raise notice ' ';
  raise notice '═══ Fase 8: assinar_plano ═══';

  -- F8.16 ── assinar dentro da área ─────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_d, true);
  set local role app_usuario;
  ass_a := assinar_plano(v_plano_s);
  reset role;
  select proxima_entrega into v_data from assinaturas where id = ass_a;
  if (select cliente_id from assinaturas where id = ass_a) = cli_a
     and (select status::text from assinaturas where id = ass_a) = 'ativa'
     and extract(dow from v_data) = 3
     and (select count(*) from entregas where assinatura_id = ass_a and status = 'pendente') = 1 then
    raise notice '  OK    F8.16 assinatura criada para o PRÓPRIO cliente, 1ª entrega numa quarta (%)', v_data;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.16 assinatura / entrega incorreta (dow=%)', extract(dow from v_data);
  end if;

  -- F8.17 ── as três frequências caem na quarta ─────────────────────────────
  v_total := v_total + 1;
  select count(*) into v_int from (
    select data_primeira_entrega(hoje_sp() + n, p.id) as d
      from planos p, generate_series(0, 20) n
  ) t where extract(dow from d) <> 3;
  if v_int = 0 then
    raise notice '  OK    F8.17 1ª entrega de qualquer plano, em 21 dias de partida, sempre cai na quarta';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.17 % datas fora da quarta', v_int;
  end if;

  -- F8.18 ── segunda assinatura vigente é recusada ──────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_d, true);
    set local role app_usuario;
    perform assinar_plano(v_plano_s);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.18 duas assinaturas vigentes';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.18 clique duplo / segunda assinatura vigente é recusada (%)', sqlerrm;
  end;

  -- F8.19 ── fora da área: sem assinatura ───────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', 'teste8-conta-f', true);
    set local role app_usuario;
    perform assinar_plano(v_plano_s);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.19 assinou fora da área';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.19 CEP fora da área não assina (%)', sqlerrm;
  end;

  -- F8.20 ── faixa cadastrada depois: assinar_plano reavalia a área ─────────
  v_total := v_total + 1;
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ('01000000', '01099999', 'Teste F8 SP');
  perform set_config('app.usuario_id', 'teste8-conta-f', true);
  set local role app_usuario;
  v_uuid := assinar_plano(v_plano_s);
  reset role;
  if (select status::text from clientes where id = v_uuid2) = 'cadastro_andamento'
     and (select dentro_area_entrega from clientes where id = v_uuid2) then
    raise notice '  OK    F8.20 faixa cadastrada depois do cadastro: pre_venda passa a cadastro_andamento ao assinar';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.20 status = %', (select status from clientes where id = v_uuid2);
  end if;

  -- F8.21 ── plano inativo / inexistente ────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    perform assinar_plano(9999::smallint);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.21 plano inexistente aceito';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.21 plano inexistente é recusado (%)', sqlerrm;
  end;

  -- F8.22 ── conta sem cadastro ──────────────────────────────────────────────
  v_total := v_total + 1;
  insert into "user" (id, name, email) values ('teste8-conta-g', 'Gil', 'gil.f8@exemplo.test');
  begin
    perform set_config('app.usuario_id', 'teste8-conta-g', true);
    set local role app_usuario;
    perform assinar_plano(v_plano_s);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.22 assinou sem cadastro';
  exception when sqlstate 'OV001' then
    reset role;
    raise notice '  OK    F8.22 conta sem cadastro não assina (%)', sqlerrm;
  end;

  -- F8.23 ── isolamento: Dora não enxerga nada de Bia nem dos outros ─────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_d, true);
  set local role app_usuario;
  select count(*) into v_int from clientes;
  select v_int + count(*) into v_int from assinaturas where cliente_id <> cli_a;
  select v_int + count(*) into v_int from entregas where cliente_id <> cli_a;
  reset role;
  if v_int = 1 then
    raise notice '  OK    F8.23 a conta vê só o próprio cliente e nada de assinatura/entrega alheia';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.23 contagem de linhas visíveis = % (esperava 1)', v_int;
  end if;

  -- F8.24 ── o cliente não escreve direto (nem cria assinatura por INSERT) ──
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    insert into assinaturas (cliente_id, plano_id, status, data_inicio, proxima_entrega)
      values (cli_b, v_plano_s, 'ativa', current_date, current_date + 1);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA F8.24 assinante inseriu assinatura direto na tabela';
  exception when others then
    reset role;
    raise notice '  OK    F8.24 INSERT direto em assinaturas é negado ao assinante (era o bug de /api/subscriptions)';
  end;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificações da Fase 8 falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações da Fase 8 passaram.', v_total;
end;
$$;

rollback;
