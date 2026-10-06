-- ═══════════════════════════════════════════════════════════════════════
-- Bloco 5 — captação de interesse fora da área.
--
--   pnpm --filter @ovo/database teste:bloco5
--
-- Tudo dentro de uma transação que termina em ROLLBACK.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_total  int := 0;
  v_falhas int := 0;
  v_int    int;
  v_ok     boolean;
  v_bool   boolean;
  v_row    record;
  id_dono  text := 'teste-b5-dono';
  id_user  text := 'teste-b5-user';
begin
  insert into "user" (id, name, email) values (id_dono, 'Dono B5', 'dono-b5@exemplo.test');
  insert into "user" (id, name, email) values (id_user, 'Assinante B5', 'user-b5@exemplo.test');
  update perfis set papel = 'dono' where id = id_dono;
  delete from faixas_cep_atendidas;   -- parte de "nenhuma área atendida"

  raise notice '═══ Bloco 5: captação de interesse ═══';

  -- B5.1 ── anon registra com telefone; número é normalizado ────────────────
  v_total := v_total + 1;
  set local role app_anon;
  perform registrar_interesse('  Maria Teste  ', '(31) 99999-0000', null, '30140-000', 'site', 1);
  reset role;
  select * into v_row from interessados where cep = '30140000';
  if v_row.nome = 'Maria Teste' and v_row.telefone = '31999990000' and v_row.email is null
     and v_row.status = 'novo' and v_row.consentimento_versao = 1 and v_row.origem = 'site' then
    raise notice '  OK    B5.1  anon registra: nome aparado, telefone e CEP só com dígitos, status "novo", consentimento v1';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.1  linha gravada: %', row_to_json(v_row);
  end if;

  -- B5.2 ── telefone com +55 e e-mail em maiúsculas são normalizados ─────────
  v_total := v_total + 1;
  set local role app_anon;
  perform registrar_interesse(null, '+55 31 98888-1111', ' JOAO@Exemplo.TEST ', '30150000', 'assinar', 1);
  reset role;
  select * into v_row from interessados where cep = '30150000';
  if v_row.telefone = '31988881111' and v_row.email = 'joao@exemplo.test' and v_row.nome is null then
    raise notice '  OK    B5.2  +55 removido, e-mail em minúsculas, nome opcional';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.2  %', row_to_json(v_row);
  end if;

  -- B5.3 ── pedido repetido não duplica e não acusa ─────────────────────────
  v_total := v_total + 1;
  set local role app_anon;
  perform registrar_interesse('Maria Teste', '31999990000', null, '30140000', 'site', 1);
  reset role;
  select count(*) into v_int from interessados where cep = '30140000';
  if v_int = 1 then
    raise notice '  OK    B5.3  o mesmo pedido de novo não cria linha nova nem dá erro';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.3  % linhas para o mesmo contato', v_int;
  end if;

  -- B5.4 ── validações: tudo que é inválido é recusado ───────────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin perform registrar_interesse('Ana', '31999990000', null, '30140000', 'site', null);   v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('Ana', '31999990000', null, '30140000', 'site', 0);      v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('Ana', null, null, '30140000', 'site', 1);               v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('Ana', '123', null, '30140000', 'site', 1);              v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('Ana', null, 'sem-arroba', '30140000', 'site', 1);       v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('Ana', '31999990000', null, '123', 'site', 1);           v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('Ana', '31999990000', null, '30140000', 'outra', 1);     v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse('A', '31999990000', null, '30140000', 'site', 1);        v_ok := false; exception when raise_exception then null; end;
  begin perform registrar_interesse(repeat('x', 121), '31999990000', null, '30140000', 'site', 1); v_ok := false; exception when raise_exception then null; end;
  if v_ok then
    raise notice '  OK    B5.4  sem consentimento, sem contato, telefone/e-mail/CEP/origem/nome inválidos: todos recusados';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.4  uma entrada inválida foi aceita';
  end if;

  -- B5.5 ── CEP já atendido: resposta igual, nada gravado ───────────────────
  v_total := v_total + 1;
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro, ativo) values ('30200000', '30299999', 'Teste B5', true);
  set local role app_anon;
  perform registrar_interesse('Carlos', '31977770000', null, '30210000', 'site', 1);
  reset role;
  select count(*) into v_int from interessados where cep = '30210000';
  if v_int = 0 then
    raise notice '  OK    B5.5  CEP já atendido não gera pedido (e a resposta é a mesma de um sucesso)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.5  gravou interessado de CEP atendido';
  end if;

  -- B5.6 ── anon e assinante não leem nem escrevem direto ───────────────────
  v_total := v_total + 1;
  v_ok := true;
  begin set local role app_anon; perform 1 from interessados limit 1; v_ok := false;
  exception when insufficient_privilege then null; end;
  reset role;
  begin set local role app_anon; insert into interessados (telefone, cep, origem, consentimento_versao) values ('31900000000', '30000000', 'site', 1); v_ok := false;
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('app.usuario_id', id_user, true);
  set local role app_usuario;
  select count(*) into v_int from interessados;   -- RLS: assinante vê 0
  if v_int <> 0 then v_ok := false; end if;
  begin update interessados set status = 'avisado'; v_ok := false;
  exception when insufficient_privilege then null; end;
  reset role;
  if v_ok then
    raise notice '  OK    B5.6  anon sem leitura/escrita; assinante vê 0 linhas e não altera nada';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.6  um papel de aplicação alcançou interessados (assinante viu % linhas)', v_int;
  end if;

  -- B5.7 ── o dono lê ─────────────────────────────────────────────────────────
  v_total := v_total + 1;
  perform set_config('app.usuario_id', id_dono, true);
  set local role app_usuario;
  select count(*) into v_int from interessados;
  reset role;
  if v_int = 2 then
    raise notice '  OK    B5.7  o dono lê os 2 pedidos válidos';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.7  dono viu % linhas (esperado 2)', v_int;
  end if;

  -- B5.8 ── faixa nova cobrindo o CEP marca "pronto para avisar" ─────────────
  v_total := v_total + 1;
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro, ativo) values ('30100000', '30149999', 'Cobre a Maria', true);
  select count(*) into v_int from interessados where cep = '30140000' and area_atendida_em is not null;
  select count(*) into v_row from interessados where cep = '30150000' and area_atendida_em is not null;
  if v_int = 1 and v_row.count = 0 then
    raise notice '  OK    B5.8  faixa nova marca só quem ela cobre (30140000 sim, 30150000 não)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.8  marcados na faixa: %, fora dela: %', v_int, v_row.count;
  end if;

  -- B5.9 ── faixa inativa não marca ─────────────────────────────────────────
  v_total := v_total + 1;
  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro, ativo) values ('30150000', '30159999', 'Inativa', false);
  select count(*) into v_int from interessados where cep = '30150000' and area_atendida_em is not null;
  if v_int = 0 then
    raise notice '  OK    B5.9  faixa inativa não marca ninguém como pronto para avisar';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.9  faixa inativa marcou interessado';
  end if;

  -- B5.10 ─ nada de telefone/e-mail na auditoria imutável ─────────────────────
  v_total := v_total + 1;
  select count(*) into v_int from auditoria
   where entidade = 'interessados'
      or dados_novos::text like '%31999990000%' or dados_anteriores::text like '%31999990000%';
  if v_int = 0 then
    raise notice '  OK    B5.10 interessados não vai para a auditoria imutável (dá para apagar a pedido do titular)';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.10 % linha(s) de auditoria com dado de interessado', v_int;
  end if;

  -- B5.11 ─ o dono apaga (pedido de exclusão) ────────────────────────────────
  v_total := v_total + 1;
  delete from interessados where cep = '30140000';
  select count(*) into v_int from interessados where cep = '30140000';
  if v_int = 0 then
    raise notice '  OK    B5.11 pedido de exclusão: a linha some de verdade';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.11 linha continuou existindo';
  end if;

  -- B5.12 ─ limite da rota "interesse": 5 por minuto ─────────────────────────
  v_total := v_total + 1;
  set local role app_anon;
  v_ok := true;
  for i in 1..5 loop
    if limitar_acesso_publico('203.0.113.90', 'interesse') then v_ok := false; end if;
  end loop;
  v_bool := limitar_acesso_publico('203.0.113.90', 'interesse');
  reset role;
  if v_ok and v_bool then
    raise notice '  OK    B5.12 5 pedidos por minuto passam; o 6º do mesmo IP é bloqueado';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA B5.12 limite (5 livres: %, 6º bloqueado: %)', v_ok, v_bool;
  end if;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception 'Bloco 5: % de % verificações falharam.', v_falhas, v_total;
  end if;
  raise notice 'As % verificações do Bloco 5 passaram.', v_total;
end;
$$;

rollback;
