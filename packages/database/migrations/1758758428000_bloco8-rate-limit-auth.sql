-- ═══════════════════════════════════════════════════════════════════════════
-- Bloco 8 — limite de tentativas de login/cadastro compartilhado entre instâncias.
--
-- O Better Auth guardava o contador na memória do processo: com várias
-- instâncias (serverless) cada uma contava separado e o limite de "5 logins por
-- minuto" virava "5 por minuto POR instância". consumir_rate_limit() faz a
-- verificação e o incremento num único comando atômico (upsert), na tabela
-- rateLimit que já existe, e é o que o `customStorage` do Better Auth chama.
--
-- Sem grant para nenhum papel de aplicação: quem a executa é a conexão do
-- Better Auth (a administrativa). Os apps não alcançam.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create function consumir_rate_limit(p_chave text, p_max integer, p_janela_segundos integer)
returns table (permitido boolean, retry_apos integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agora timestamptz := clock_timestamp();
  v_count integer;
  v_reset timestamptz;
begin
  if p_chave is null or p_chave = '' or char_length(p_chave) > 300
     or p_max is null or p_max < 1 or p_janela_segundos is null or p_janela_segundos < 1 then
    raise exception 'Parâmetros de limite inválidos.';
  end if;

  -- Atômico: duas requisições simultâneas nunca leem o mesmo contador "velho".
  -- Janela vencida reinicia em 1; senão incrementa (com teto, para nunca estourar o inteiro).
  insert into rateLimit as r (ip, endpoint, count, reset_at)
  values (p_chave, 'auth', 1, v_agora + make_interval(secs => p_janela_segundos))
  on conflict (ip, endpoint) do update
    set count    = case when r.reset_at <= v_agora then 1 else least(r.count + 1, 1000000) end,
        reset_at = case when r.reset_at <= v_agora then excluded.reset_at else r.reset_at end
  returning r.count, r.reset_at into v_count, v_reset;

  return query select v_count <= p_max,
                      greatest(1, ceil(extract(epoch from (v_reset - v_agora)))::integer);
end;
$$;

comment on function consumir_rate_limit(text, integer, integer) is
  'Contador atômico por chave (ex.: "ip|/sign-in/email") numa janela de p_janela_segundos. permitido = false quando o limite p_max já foi atingido; retry_apos = segundos até a janela liberar. Só a conexão do Better Auth a executa.';

revoke execute on function consumir_rate_limit(text, integer, integer) from public;


-- Down Migration

drop function if exists consumir_rate_limit(text, integer, integer);
