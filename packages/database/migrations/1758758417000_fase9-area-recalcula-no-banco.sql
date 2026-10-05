-- ═══════════════════════════════════════════════════════════════════════════
-- Fase 9 (auditoria de estabilidade) — a área de entrega se recalcula sozinha.
--
-- `clientes.dentro_area_entrega` é um valor guardado, calculado a partir do CEP
-- e das faixas ativas. Até aqui quem reavaliava os clientes quando uma faixa
-- mudava era o código do painel (`recalcularClientes`, em cada ação). Qualquer
-- mudança feita por outro caminho (SQL direto, outra tela futura) deixava
-- clientes com o valor velho — e é esse valor que libera ou bloqueia assinatura,
-- entrega e reativação. Achado ao desativar uma faixa por SQL: os clientes
-- continuaram "dentro da área".
--
-- Agora o próprio banco reavalia, só dos clientes cujo resultado mudou.
-- ═══════════════════════════════════════════════════════════════════════════

-- Up Migration

create or replace function faixas_reavaliam_clientes()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  update clientes
     set cep = cep
   where cep is not null
     and dentro_area_entrega is distinct from cep_dentro_area_entrega(cep);
  return null;
end;
$$;

revoke execute on function faixas_reavaliam_clientes() from public;

create trigger faixas_reavaliam_clientes_tg
  after insert or update or delete on faixas_cep_atendidas
  for each statement execute function faixas_reavaliam_clientes();

-- Corrige o que já estiver desatualizado.
update clientes
   set cep = cep
 where cep is not null
   and dentro_area_entrega is distinct from cep_dentro_area_entrega(cep);


-- Down Migration

drop trigger if exists faixas_reavaliam_clientes_tg on faixas_cep_atendidas;
drop function if exists faixas_reavaliam_clientes();
