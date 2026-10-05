-- ═══════════════════════════════════════════════════════════════════════
-- Teste 2 do prompt (escalada de papel) + isolamento entre contas.
--
--   pnpm --filter @ovo/database teste:autorizacao
--
-- Simula o que o servidor faz a cada requisição: `set local role` mais o
-- parâmetro `app.usuario_id`, que é o que app.usuario_id() lê.
--
-- Tudo dentro de uma transação que termina em ROLLBACK: o banco fica
-- exatamente como estava, sem usuário de teste sobrando.
--
-- Os itens marcados CONTROLE POSITIVO existem porque, sem eles, uma
-- conexão errada faz tudo falhar e o relatório fica verde pelo motivo
-- errado.
-- ═══════════════════════════════════════════════════════════════════════

begin;

do $$
declare
  id_a       text := 'teste-conta-a';
  id_b       text := 'teste-conta-b';
  v_papel    text;
  v_nome     text;
  v_linhas   int;
  v_falhas   int := 0;
  v_total    int := 0;
  cli_a      uuid;
  cli_b      uuid;
  v_texto    text;
  v_bool     boolean;


  -- acumulador do relatório
  v_relato text := '';

begin
  insert into "user" (id, name, email) values (id_a, 'Assinante A', 'a@exemplo.test');
  insert into "user" (id, name, email) values (id_b, 'Assinante B', 'b@exemplo.test');

  -- 1 ────────────────────────────────────────────────────────────────
  select papel::text into v_papel from perfis where id = id_a;
  v_total := v_total + 1;
  if v_papel = 'assinante' then
    raise notice '  OK    1. perfil nasce como assinante (papel: %)', v_papel;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 1. perfil nasce como assinante — papel gravado: %', v_papel;
  end if;

  -- 2 ────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    update perfis set papel = 'dono' where id = id_b;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 2. assinante nao grava papel=dono — O UPDATE PASSOU';
  exception when others then
    raise notice '  OK    2. assinante nao grava papel=dono (recusado: %)', sqlerrm;
  end;

  -- 3 ────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    perform definir_papel(id_b, 'dono'::papel_usuario);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 3. assinante nao executa definir_papel() — A FUNCAO RESPONDEU';
  exception when others then
    raise notice '  OK    3. assinante nao executa definir_papel() (recusado: %)', sqlerrm;
  end;

  select papel::text into v_papel from perfis where id = id_b;
  v_total := v_total + 1;
  if v_papel = 'assinante' then
    raise notice '  OK    4. papel de B continua assinante';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 4. papel de B virou %', v_papel;
  end if;

  -- 5 ────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    select count(*) into v_linhas from perfis where id = id_a;
    reset role;
    if v_linhas = 0 then
      raise notice '  OK    5. B nao le o perfil de A';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 5. B leu % linha(s) do perfil de A', v_linhas;
    end if;
  exception when others then
    raise notice '  OK    5. B nao le o perfil de A (recusado: %)', sqlerrm;
  end;

  -- 6 ────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    update perfis set nome = 'Invadido' where id = id_a;
    reset role;
  exception when others then
    null;
  end;
  select nome into v_nome from perfis where id = id_a;
  if v_nome <> 'Invadido' then
    raise notice '  OK    6. B nao altera o perfil de A (nome segue: %)', v_nome;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 6. B ALTEROU o perfil de A';
  end if;

  -- 7 ────────────────────────────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    delete from perfis where id = id_a;
    reset role;
  exception when others then
    null;
  end;
  if exists (select 1 from perfis where id = id_a) then
    raise notice '  OK    7. B nao apaga o perfil de A';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 7. O PERFIL DE A SUMIU';
  end if;

  -- 8 ─── CONTROLE POSITIVO ───────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    update perfis set nome = 'Nome novo de B' where id = id_b;
    reset role;
    select nome into v_nome from perfis where id = id_b;
    if v_nome = 'Nome novo de B' then
      raise notice '  OK    8. CONTROLE POSITIVO: B altera o proprio nome';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 8. CONTROLE POSITIVO falhou — nome: %', v_nome;
    end if;
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 8. CONTROLE POSITIVO falhou — erro: %', sqlerrm;
  end;

  -- 9 ─── sem contexto, ninguem ve nada ───────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', '', true);
    set local role app_usuario;
    select count(*) into v_linhas from perfis;
    reset role;
    if v_linhas = 0 then
      raise notice '  OK    9. sem app.usuario_id setado, app_usuario nao ve nada';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 9. sem contexto, app_usuario viu % linha(s)', v_linhas;
    end if;
  exception when others then
    raise notice '  OK    9. sem contexto, app_usuario nao ve nada (recusado: %)', sqlerrm;
  end;

  -- 10 ── anon nao le perfis ──────────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', '', true);
    set local role app_anon;
    select count(*) into v_linhas from perfis;
    reset role;
    if v_linhas = 0 then
      raise notice '  OK    10. app_anon nao le a tabela de perfis';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 10. app_anon leu % linha(s)', v_linhas;
    end if;
  exception when others then
    raise notice '  OK    10. app_anon nao le a tabela de perfis (recusado: %)', sqlerrm;
  end;

  -- 11 ── as tabelas de credencial sao inalcancaveis ──────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    select count(*) into v_linhas from "account";
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 11. app_usuario LEU a tabela de credenciais (hash de senha)';
  exception when others then
    raise notice '  OK    11. app_usuario nao alcanca "account", onde mora o hash de senha';
  end;

  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    select count(*) into v_linhas from "session";
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 12. app_usuario LEU a tabela de sessoes (token)';
  exception when others then
    raise notice '  OK    12. app_usuario nao alcanca "session", onde mora o token';
  end;

  -- 13 ── criado_em imutavel, ate pela conexao administrativa ─────────
  v_total := v_total + 1;
  begin
    update perfis
       set criado_em = timestamptz '2000-01-01 00:00:00+00',
           nome = 'B reescrevendo o passado'
     where id = id_b;
    if (select criado_em from perfis where id = id_b) > timestamptz '2020-01-01 00:00:00+00' then
      raise notice '  OK    13. criado_em e imutavel mesmo pela conexao administrativa';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 13. criado_em foi reescrito';
    end if;
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 13. erro: %', sqlerrm;
  end;

  -- 14 ── DEFESA EM PROFUNDIDADE ──────────────────────────────────────
  -- Ate aqui, quem barrou o assinante no item 2 foi o GRANT DE COLUNA.
  -- A pergunta que importa e outra: se alguem amanha afrouxar esse grant
  -- sem perceber o que esta abrindo, a policy ainda segura sozinha?
  v_total := v_total + 1;
  grant update (papel) on perfis to app_usuario;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    update perfis set papel = 'dono' where id = id_b;
    reset role;
  exception when others then
    raise notice '        (a policy recusou: %)', sqlerrm;
  end;
  select papel::text into v_papel from perfis where id = id_b;
  if v_papel <> 'dono' then
    raise notice '  OK    14. com o grant afrouxado, a policy sozinha ainda barra';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 14. COM O GRANT AFROUXADO, O ASSINANTE VIROU DONO';
  end if;
  revoke update (papel) on perfis from app_usuario;

  -- 15 ── CONTROLE POSITIVO: o dono troca papel pelo caminho certo ────
  v_total := v_total + 1;
  update perfis set papel = 'dono' where id = id_a;
  begin
    perform set_config('app.usuario_id', id_a, true);
    set local role app_usuario;
    perform definir_papel(id_b, 'dono'::papel_usuario);
    reset role;
    select papel::text into v_papel from perfis where id = id_b;
    if v_papel = 'dono' then
      raise notice '  OK    15. CONTROLE POSITIVO: dono troca papel por definir_papel()';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 15. papel de B ficou %', v_papel;
    end if;
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 15. CONTROLE POSITIVO falhou — erro: %', sqlerrm;
  end;


  -- ══════════════════════════════════════════════════════════════════
  -- Fase 1 — o teste das duas contas sobre dado de negocio de verdade
  -- ══════════════════════════════════════════════════════════════════

  -- O item 15 acabou de promover B a dono, de proposito. Se os testes
  -- seguintes rodassem assim, B enxergaria tudo POR SER ADMINISTRADOR e o
  -- resultado nao provaria nada sobre isolamento. Volta os dois para
  -- assinante antes de continuar.
  update perfis set papel = 'assinante' where id in (id_a, id_b);

  insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro)
  values ('30110000', '30190999', 'Centro-Sul');

  insert into clientes (usuario_id, nome, telefone, cep, endereco, origem)
  values (id_a, 'Ana Antunes', '+5531999990001', '30140000', 'Rua A, 10', 'organico')
  returning id into cli_a;

  insert into clientes (usuario_id, nome, telefone, cep, endereco, origem)
  values (id_b, 'Bruno Barros', '+5531999990002', '31000000', 'Rua B, 20', 'indicacao')
  returning id into cli_b;

  -- 16 ── B nao le o cliente de A ─────────────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    select count(*) into v_linhas from clientes where id = cli_a;
    reset role;
    if v_linhas = 0 then
      raise notice '  OK    16. B nao le o cliente de A';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 16. B leu o cliente de A';
    end if;
  exception when others then
    raise notice '  OK    16. B nao le o cliente de A (recusado: %)', sqlerrm;
  end;

  -- 17 ── B nao altera o cliente de A pela funcao ─────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    perform atualizar_meus_dados(cli_a, p_endereco := 'Invadido');
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 17. B ALTEROU o cliente de A pela funcao';
  exception when others then
    raise notice '  OK    17. B nao altera o cliente de A (recusado: %)', sqlerrm;
  end;

  -- 18 ── ninguem escreve direto na tabela ────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    update clientes set endereco = 'Direto' where id = cli_b;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 18. UPDATE direto em clientes passou';
  exception when others then
    raise notice '  OK    18. ninguem escreve direto em clientes (recusado: %)', sqlerrm;
  end;

  -- 19 ── CONTROLE POSITIVO: B altera os proprios dados ───────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    perform atualizar_meus_dados(cli_b, p_endereco := 'Rua Nova, 99', p_telefone := '31988887777');
    reset role;
    select endereco into v_texto from clientes where id = cli_b;
    if v_texto = 'Rua Nova, 99' then
      raise notice '  OK    19. CONTROLE POSITIVO: B altera os proprios dados';
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 19. endereco ficou: %', v_texto;
    end if;
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 19. CONTROLE POSITIVO falhou: %', sqlerrm;
  end;

  -- 20 ── area de entrega e calculada, nunca recebida ─────────────────
  v_total := v_total + 1;
  select dentro_area_entrega into v_bool from clientes where id = cli_a;
  if v_bool then
    raise notice '  OK    20a. CEP dentro da faixa marca dentro_area_entrega';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 20a. CEP 30140000 esta na faixa e nao foi marcado';
  end if;

  v_total := v_total + 1;
  update clientes set dentro_area_entrega = true where id = cli_b;  -- CEP 31000000, fora
  select dentro_area_entrega into v_bool from clientes where id = cli_b;
  if not v_bool then
    raise notice '  OK    20b. dentro_area_entrega forcado a true foi recalculado para false';
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 20b. DEU PARA SE DECLARAR DENTRO DA AREA DE ENTREGA';
  end if;

  -- 21 ── codigo de indicacao gerado, unico e sem caractere ambiguo ───
  v_total := v_total + 1;
  select codigo_indicacao into v_texto from clientes where id = cli_a;
  if v_texto ~ '^ONCA-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$' then
    raise notice '  OK    21. codigo de indicacao gerado no formato certo (%)', v_texto;
  else
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 21. codigo fora do formato: %', v_texto;
  end if;

  -- 22 ── B nao rouba o codigo de indicacao de A ──────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', id_b, true);
    set local role app_usuario;
    perform atualizar_meus_dados(cli_b, p_codigo_indicacao := v_texto);
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 22. B ROUBOU o codigo de indicacao de A';
  exception when others then
    raise notice '  OK    22. B nao rouba o codigo de indicacao de A (recusado: %)', sqlerrm;
  end;

  -- 23 ── nome_do_indicador devolve so o primeiro nome ────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', '', true);
    set local role app_anon;
    select nome_do_indicador(v_texto) into v_texto;
    reset role;
    if v_texto = 'Ana' then
      raise notice '  OK    23. nome_do_indicador devolve so o primeiro nome (%)', v_texto;
    else
      v_falhas := v_falhas + 1;
      raise notice '  FALHA 23. devolveu: %', v_texto;
    end if;
  exception when others then
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 23. erro: %', sqlerrm;
  end;

  -- 24 ── anon nao le a tabela de clientes ────────────────────────────
  v_total := v_total + 1;
  begin
    perform set_config('app.usuario_id', '', true);
    set local role app_anon;
    select count(*) into v_linhas from clientes;
    reset role;
    v_falhas := v_falhas + 1;
    raise notice '  FALHA 24. anon leu % cliente(s)', v_linhas;
  exception when others then
    raise notice '  OK    24. anon nao le a tabela de clientes (recusado: %)', sqlerrm;
  end;

  raise notice ' ';
  if v_falhas > 0 then
    raise exception '% de % verificacoes falharam. Nao existe sistema ainda.', v_falhas, v_total;
  end if;
  raise notice 'As % verificacoes passaram. A fundacao e a camada de clientes estao de pe.', v_total;
end;
$$;

rollback;
