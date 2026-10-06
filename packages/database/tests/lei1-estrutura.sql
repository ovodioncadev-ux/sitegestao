-- ═══════════════════════════════════════════════════════════════════════
-- Verificações estruturais da Fase 0.
--
--   pnpm --filter @ovo/database teste:estrutura
--
-- Precisa terminar sem erro. Cada bloco estoura de propósito se achar
-- algo — é assim que ele reprova o deploy.
-- ═══════════════════════════════════════════════════════════════════════

-- Lei 1 — nenhuma policy de UPDATE/ALL sem `with check`.
-- O `using` diz quais LINHAS a pessoa alcança. O `with check` diz O QUE ela
-- pode gravar. Sem o segundo, quem alcança a linha escreve qualquer valor.
do $$
declare v_lista text;
begin
  select coalesce(string_agg(tablename || '.' || policyname, ', '), '')
    into v_lista
  from pg_policies
  where schemaname = 'public' and cmd in ('UPDATE', 'ALL') and with_check is null;

  if v_lista <> '' then
    raise exception 'Lei 1 violada — policy de update sem with check: %', v_lista;
  end if;
  raise notice '  OK  Lei 1: nenhuma policy de update sem with check';
end;
$$;

-- RLS ligada em toda tabela do schema public.
do $$
declare v_lista text;
begin
  select coalesce(string_agg(c.relname, ', '), '')
    into v_lista
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
    and c.relname <> 'pgmigrations';   -- controle do migrador, sem dado de cliente

  if v_lista <> '' then
    raise exception 'Tabelas sem RLS no schema public: %', v_lista;
  end if;
  raise notice '  OK  RLS ligada em todas as tabelas de negocio';
end;
$$;

-- Nenhuma função alcançável pelos papéis de aplicação sem ter sido
-- concedida de propósito. Era assim que uma função interna virava RPC
-- pública quando um `drop` apagava o revoke em silêncio.
do $$
declare v_lista text;
begin
  select coalesce(string_agg(distinct n.nspname || '.' || p.proname, ', '), '')
    into v_lista
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app')
    and p.prokind = 'f'
    -- Lista das funcoes concedidas DE PROPOSITO a um papel de aplicacao.
    -- Acrescentar um nome aqui e um ato consciente: se uma funcao aparecer
    -- no relatorio, ou ela nao devia estar alcancavel, ou alguem precisa
    -- decidir que ela deve e escrever o nome nesta lista.
    and p.proname not in (
      'meu_papel', 'sou_dono', 'definir_papel', 'usuario_id',
      'cep_dentro_area_entrega',   -- a tela de cadastro consulta antes de haver conta
      'nome_do_indicador',         -- publica declarada: devolve so o primeiro nome
      'atualizar_meus_dados',      -- confere a posse do registro na primeira instrucao
      'solicitar_alteracao_assinatura',  -- confere a posse da assinatura na primeira instrucao
      'planos_publicos',           -- vitrine: so id, nome, intervalo, preco derivado e regras de exibicao
      'criar_meu_cadastro',        -- cria o cliente da PROPRIA conta (identidade vem da sessao)
      'assinar_plano',             -- assina para o PROPRIO cliente (identidade vem da sessao)
      'site_conteudo',             -- vitrine: frescor, frete, desconto e corte derivados dos planos ativos
      'limitar_acesso_publico',    -- contador por IP de rotas publicas; rotas e limites fixos no corpo
      'registrar_evento_funil',    -- conta etapa e plano publico do funil; sem dado pessoal, etapas em lista fechada
      'registrar_interesse',       -- pedido de aviso de quem esta fora da area; valida, exige consentimento, sem leitura
      'iniciar_pagamento_online',  -- devolve valor e referencia so da PROPRIA fatura em aberto (confere a posse)
      'anexar_link_pagamento'      -- grava o link https na PROPRIA fatura em aberto (confere a posse)
    )
    and (
      has_function_privilege('app_anon', p.oid, 'execute')
      or has_function_privilege('app_usuario', p.oid, 'execute')
    );

  if v_lista <> '' then
    raise exception 'Funcoes alcancaveis pelos papeis de aplicacao sem concessao explicita: %', v_lista;
  end if;
  raise notice '  OK  nenhuma funcao exposta por acidente';
end;
$$;

-- search_path fixo em toda função. search_path mutável é vetor de escalada.
do $$
declare v_lista text;
begin
  select coalesce(string_agg(n.nspname || '.' || p.proname, ', '), '')
    into v_lista
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'app')
    and p.prokind = 'f'
    and not exists (
      select 1 from unnest(coalesce(p.proconfig, '{}')) cfg where cfg like 'search_path=%'
    );

  if v_lista <> '' then
    raise exception 'Funcoes sem "set search_path": %', v_lista;
  end if;
  raise notice '  OK  search_path fixo em todas as funcoes';
end;
$$;

-- As tabelas do Better Auth guardam hash de senha e token: nenhum papel
-- de aplicação pode ter privilégio nelas.
do $$
declare v_lista text;
begin
  select coalesce(string_agg(distinct t.tabela, ', '), '')
    into v_lista
  from (values ('user'), ('session'), ('account'), ('verification')) as t(tabela)
  where has_table_privilege('app_anon', format('public.%I', t.tabela), 'select')
     or has_table_privilege('app_usuario', format('public.%I', t.tabela), 'select');

  if v_lista <> '' then
    raise exception 'Papel de aplicacao alcanca tabela de credencial: %', v_lista;
  end if;
  raise notice '  OK  tabelas de credencial inalcancaveis pelos papeis de aplicacao';
end;
$$;

do $$ begin raise notice ' '; raise notice 'Verificacoes estruturais da Fase 0: todas passaram.'; end; $$;
