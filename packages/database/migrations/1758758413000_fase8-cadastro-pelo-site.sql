-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 8 — cadastro e assinatura feitos pelo próprio cliente, no site.
--
-- Três mudanças:
--
--   1. VÍNCULO POR E-MAIL SÓ COM E-MAIL CONFIRMADO. A Fase 7 ligava conta a
--      cliente pelo e-mail sem confirmar que a pessoa é dona dele: quem criasse
--      uma conta com o e-mail de outro cliente passava a ver o endereço, o
--      telefone e as faturas dele. Agora o vínculo automático exige
--      "user"."emailVerified" = true (Google confirma; e-mail e senha passam a
--      confirmar quando houver serviço de e-mail configurado). Até lá, o dono
--      vincula na mão pela ficha do cliente.
--
--   2. PLANOS PÚBLICOS SEM PREÇO NO CÓDIGO. O preço do plano é derivado do
--      banco (pente × entregas_por_mes), a mesma conta de calcular_valor_fatura.
--      Antes ele era um CASE com 16400/8200/4100 escrito na rota da API.
--
--   3. CADASTRO E ASSINATURA PELO CLIENTE, por duas funções com lista fechada
--      de campos e posse derivada da sessão:
--        criar_meu_cadastro()  cria o registro de cliente da conta logada
--        assinar_plano()       cria a assinatura (e a 1ª entrega) da conta logada
--      O cliente NÃO informa id, e-mail, status, preço nem data: o e-mail vem
--      da conta, o status é decidido aqui, a data cai na quarta pelas mesmas
--      regras de criar_assinatura().
--
-- Fora da área de entrega o cliente é cadastrado como `pre_venda` e NÃO ganha
-- assinatura — é a interpretação já adotada em DECISOES/PROGRESSO.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Vínculo por e-mail: só com e-mail confirmado
-- ───────────────────────────────────────────────────────────────────────────
create or replace function vincular_conta_ao_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new."emailVerified" is not true then
    return null;
  end if;

  -- Só conta de assinante (nunca a do dono) e só se ainda não tem cliente.
  if exists (select 1 from perfis where id = new.id and papel = 'assinante')
     and not exists (select 1 from clientes where usuario_id = new.id)
  then
    update clientes
       set usuario_id = new.id
     where id = (
       select c.id from clientes c
        where lower(c.email) = lower(new.email)
          and c.usuario_id is null
        limit 1
     );
  end if;
  return null;
end;
$$;

-- E-mail confirmado depois do cadastro (link enviado por e-mail) também vincula.
create trigger user_vincula_cliente_ao_verificar_tg
  after update of "emailVerified" on "user"
  for each row
  when (new."emailVerified" is true and old."emailVerified" is distinct from true)
  execute function vincular_conta_ao_cliente();

revoke execute on function vincular_conta_ao_cliente() from public;


create or replace function clientes_vincula_conta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.usuario_id is not null or new.email is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.email is not distinct from new.email then
    return new;      -- salvar sem trocar o e-mail não religa uma conta desvinculada
  end if;

  select u.id into new.usuario_id
    from "user" u
    join perfis p on p.id = u.id
   where lower(u.email) = lower(new.email)
     and u."emailVerified" is true
     and p.papel = 'assinante'
     and not exists (select 1 from clientes c where c.usuario_id = u.id and c.id is distinct from new.id)
   limit 1;

  return new;
end;
$$;

revoke execute on function clientes_vincula_conta() from public;


-- ───────────────────────────────────────────────────────────────────────────
-- 2. Planos públicos
--
-- security definer porque o anônimo não lê config_negocio (o preço do pente
-- mora lá). Devolve só o que a vitrine mostra.
-- ───────────────────────────────────────────────────────────────────────────
create or replace function planos_publicos()
returns table (
  id                        smallint,
  frequencia                text,
  nome                      text,
  intervalo_dias            smallint,
  ancorar_em_quarta         boolean,
  preco_centavos            integer,
  freshness_max_dias        smallint,
  frete_centavos            integer,
  desconto_primeiro_mes_pct numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.frequencia::text, p.nome, p.intervalo_dias, p.ancorar_em_quarta,
         (c.preco_pente_centavos * p.entregas_por_mes)::integer,
         p.freshness_max_dias, p.frete_centavos, p.desconto_primeiro_mes_pct
    from planos p
    cross join config_negocio c
   where p.ativo and c.id = 1
   order by p.intervalo_dias;
$$;

comment on function planos_publicos() is
  'Vitrine de planos para quem não está logado. Preço = preço do pente × entregas por mês (1 pente por entrega, como calcular_valor_fatura). Sem preço no código.';

revoke execute on function planos_publicos() from public;
grant  execute on function planos_publicos() to app_anon, app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 3a. criar_meu_cadastro
-- ───────────────────────────────────────────────────────────────────────────
create or replace function criar_meu_cadastro(
  p_nome        text,
  p_telefone    text,
  p_cep         text,
  p_endereco    text,
  p_numero      text,
  p_complemento text,
  p_bairro      text,
  p_cidade      text,
  p_estado      text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuario  text := app.usuario_id();
  v_email    text;
  v_nome     text := trim(coalesce(p_nome, ''));
  v_telefone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_cep      text := regexp_replace(coalesce(p_cep, ''), '\D', '', 'g');
  v_endereco text := trim(coalesce(p_endereco, ''));
  v_numero   text := trim(coalesce(p_numero, ''));
  v_compl    text := nullif(trim(coalesce(p_complemento, '')), '');
  v_bairro   text := trim(coalesce(p_bairro, ''));
  v_cidade   text := trim(coalesce(p_cidade, ''));
  v_estado   text := upper(trim(coalesce(p_estado, '')));
  v_id       uuid;
begin
  -- Identidade sempre da sessão; nada disto vem do formulário.
  if v_usuario is null then
    raise exception 'Sessão expirada. Entre de novo.' using errcode = 'OV001';
  end if;

  if not exists (select 1 from perfis where id = v_usuario and papel = 'assinante') then
    raise exception 'Você não tem permissão para realizar esta ação.' using errcode = 'OV001';
  end if;

  if exists (select 1 from clientes where usuario_id = v_usuario) then
    raise exception 'Você já tem um cadastro. Use "Meus dados" para alterá-lo.' using errcode = 'OV001';
  end if;

  select u.email into v_email from "user" u where u.id = v_usuario;
  if v_email is null then
    raise exception 'Sessão expirada. Entre de novo.' using errcode = 'OV001';
  end if;

  if char_length(v_nome) not between 3 and 120 then
    raise exception 'Nome precisa ter entre 3 e 120 caracteres.' using errcode = 'OV001';
  end if;
  if left(v_telefone, 2) = '55' and length(v_telefone) in (12, 13) then
    v_telefone := substr(v_telefone, 3);
  end if;
  if length(v_telefone) not between 10 and 11 then
    raise exception 'Telefone precisa ter 10 ou 11 dígitos (com DDD).' using errcode = 'OV001';
  end if;
  if length(v_cep) <> 8 then
    raise exception 'CEP precisa ter 8 dígitos.' using errcode = 'OV001';
  end if;
  if char_length(v_endereco) not between 2 and 200 then
    raise exception 'Rua é obrigatória (até 200 caracteres).' using errcode = 'OV001';
  end if;
  if char_length(v_numero) not between 1 and 20 then
    raise exception 'Número é obrigatório (até 20 caracteres).' using errcode = 'OV001';
  end if;
  if v_compl is not null and char_length(v_compl) > 100 then
    raise exception 'Complemento passa de 100 caracteres.' using errcode = 'OV001';
  end if;
  if char_length(v_bairro) not between 2 and 100 then
    raise exception 'Bairro é obrigatório.' using errcode = 'OV001';
  end if;
  if char_length(v_cidade) not between 2 and 100 then
    raise exception 'Cidade é obrigatória.' using errcode = 'OV001';
  end if;
  if v_estado !~ '^[A-Z]{2}$' then
    raise exception 'Estado inválido. Use a sigla, como MG.' using errcode = 'OV001';
  end if;

  begin
    insert into clientes (
      usuario_id, tipo, status, nome, telefone, email,
      cep, endereco, numero, complemento, bairro, cidade, estado, origem
    ) values (
      v_usuario, 'b2c',
      -- Fora da área: funil (pre_venda), não recusa. Ver comment on type status_cliente.
      case when cep_dentro_area_entrega(v_cep) then 'cadastro_andamento' else 'pre_venda' end::status_cliente,
      v_nome, '+55' || v_telefone, v_email,
      v_cep, v_endereco, v_numero, v_compl, v_bairro, v_cidade, v_estado,
      'organico'
    )
    returning id into v_id;
  exception when unique_violation then
    -- Não diz QUAL dado colidiu: o e-mail já pode estar no cadastro de outra pessoa.
    raise exception 'Não foi possível criar o cadastro com este e-mail. Fale com a Ovo di Onça.' using errcode = 'OV001';
  end;

  return v_id;
end;
$$;

comment on function criar_meu_cadastro(text, text, text, text, text, text, text, text, text) is
  'A conta logada cria o PRÓPRIO registro de cliente. E-mail vem da conta; status e origem são decididos aqui; fora da área vira pre_venda.';

revoke execute on function criar_meu_cadastro(text, text, text, text, text, text, text, text, text) from public;
grant  execute on function criar_meu_cadastro(text, text, text, text, text, text, text, text, text) to app_usuario;


-- ───────────────────────────────────────────────────────────────────────────
-- 3b. assinar_plano
-- ───────────────────────────────────────────────────────────────────────────
create or replace function assinar_plano(p_plano smallint)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente uuid;
begin
  -- Posse: o cliente é o da sessão. Nada de id vindo de fora.
  select c.id into v_cliente from clientes c where c.usuario_id = app.usuario_id();
  if v_cliente is null then
    raise exception 'Complete seu cadastro antes de assinar.' using errcode = 'OV001';
  end if;

  -- Refaz o cálculo da área: as faixas podem ter sido cadastradas depois do cadastro.
  update clientes set atualizado_em = now() where id = v_cliente;
  update clientes set status = 'cadastro_andamento'
   where id = v_cliente and status = 'pre_venda' and dentro_area_entrega;

  -- Regras de área, endereço, plano ativo, assinatura única e data na quarta
  -- ficam todas em criar_assinatura(), a mesma que o painel do dono usa.
  return criar_assinatura(v_cliente, p_plano);
end;
$$;

comment on function assinar_plano(smallint) is
  'A conta logada assina um plano para o PRÓPRIO cadastro. Usa criar_assinatura(): bloqueia fora da área, exige endereço, uma assinatura vigente por cliente, 1ª entrega na quarta. Não cria fatura nem cobra: pagamento segue manual.';

revoke execute on function assinar_plano(smallint) from public;
grant  execute on function assinar_plano(smallint) to app_usuario;


-- Down Migration

drop function if exists assinar_plano(smallint);
drop function if exists criar_meu_cadastro(text, text, text, text, text, text, text, text, text);
drop function if exists planos_publicos();
drop trigger if exists user_vincula_cliente_ao_verificar_tg on "user";

-- Volta o vínculo da Fase 7 (sem exigir e-mail confirmado).
create or replace function clientes_vincula_conta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.usuario_id is not null or new.email is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.email is not distinct from new.email then
    return new;
  end if;

  select u.id into new.usuario_id
    from "user" u
    join perfis p on p.id = u.id
   where lower(u.email) = lower(new.email)
     and p.papel = 'assinante'
     and not exists (select 1 from clientes c where c.usuario_id = u.id and c.id is distinct from new.id)
   limit 1;

  return new;
end;
$$;

create or replace function vincular_conta_ao_cliente()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from clientes where usuario_id = new.id) then
    update clientes
       set usuario_id = new.id
     where lower(email) = lower(new.email)
       and usuario_id is null;
  end if;
  return null;
end;
$$;
