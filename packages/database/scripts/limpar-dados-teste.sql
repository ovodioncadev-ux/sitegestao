-- Remove os dados de teste manual/E2E: tudo que tem nome "[TESTE]…" ou conta
-- "@ovo-teste.test". Só apaga isso, e só dados de negócio e contas de teste.
-- A tabela de auditoria NÃO é tocada (é imutável): o histórico das ações de
-- teste continua lá, e é isso mesmo.
--
--   pnpm db:limpar-teste
--
-- Confira o que será removido antes:
--   select nome from clientes where nome like '[TESTE]%';
--   select email from "user" where email like '%@ovo-teste.test';

begin;

create temp table _clientes_teste on commit drop as
  select id from clientes where nome like '[TESTE]%' or email like '%@ovo-teste.test';

create temp table _assinaturas_teste on commit drop as
  select id from assinaturas where cliente_id in (select id from _clientes_teste);

delete from reposicoes              where assinatura_id in (select id from _assinaturas_teste);
delete from solicitacoes_assinatura where assinatura_id in (select id from _assinaturas_teste);
delete from faturas                 where assinatura_id in (select id from _assinaturas_teste);
delete from entregas                where assinatura_id in (select id from _assinaturas_teste);
delete from assinaturas             where id in (select id from _assinaturas_teste);
delete from clientes                where id in (select id from _clientes_teste);
delete from faixas_cep_atendidas    where bairro like '[TESTE]%';
-- session, account e perfis saem junto (on delete cascade).
delete from "user"                  where email like '%@ovo-teste.test';

do $$
begin
  raise notice 'Clientes restantes: %  |  contas restantes: %',
    (select count(*) from clientes), (select count(*) from "user");
end $$;

commit;
