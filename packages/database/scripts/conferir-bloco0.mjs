#!/usr/bin/env node
/**
 * BLOCO 0 — conferência SOMENTE LEITURA (begin read only + rollback).
 * Não altera nada e não imprime connection string.
 *
 *   node packages/database/scripts/conferir-bloco0.mjs
 *
 * Mostra, no banco PRINCIPAL (DATABASE_ADMIN_URL) e no branch de TESTE
 * (DATABASE_TEST_URL):
 *   - se a conta e2e-dono@ovo-teste.test existe e com qual papel;
 *   - quantos usuários têm papel dono (e quais e-mails);
 *   - quantas linhas começam com "[TESTE]", por tabela.
 */
import pg from 'pg';
import { carregarEnv } from './banco-teste.mjs';

carregarEnv();

const alvos = [
  ['PRINCIPAL', process.env.DATABASE_ADMIN_URL],
  ['TESTE', process.env.DATABASE_TEST_URL],
];

for (const [nome, url] of alvos) {
  console.log(`\n══ ${nome} ══`);
  if (!url) { console.log('  (URL não configurada no .env)'); continue; }
  const c = new pg.Client({ connectionString: url, connectionTimeoutMillis: 20000 });
  try {
    await c.connect();
    await c.query('begin read only');

    const e2e = (await c.query(
      `select u.email, u.name, p.papel from "user" u left join perfis p on p.id = u.id
        where u.email = 'e2e-dono@ovo-teste.test'`)).rows;
    console.log('conta e2e-dono@ovo-teste.test:', e2e.length ? JSON.stringify(e2e) : 'NÃO EXISTE');

    const donos = (await c.query(
      `select u.email from perfis p join "user" u on u.id = p.id where p.papel = 'dono' order by 1`)).rows;
    console.log(`usuários com papel dono: ${donos.length}`);
    for (const d of donos) console.log('  -', d.email);

    const contas = (await c.query(`select count(*)::int n from "user" where email like '%@ovo-teste.test'`)).rows[0].n;
    console.log(`contas @ovo-teste.test: ${contas}`);

    const cols = (await c.query(
      `select table_name, column_name from information_schema.columns
        where table_schema = 'public' and data_type in ('text', 'character varying')
        order by 1, 2`)).rows;
    const porTabela = new Map();
    for (const { table_name, column_name } of cols) {
      if (!porTabela.has(table_name)) porTabela.set(table_name, []);
      porTabela.get(table_name).push(column_name);
    }
    let total = 0;
    const achados = [];
    for (const [tabela, cs] of porTabela) {
      const cond = cs.map((x) => `"${x}" like '[TESTE]%'`).join(' or ');
      const n = (await c.query(`select count(*)::int n from "${tabela}" where ${cond}`)).rows[0].n;
      if (n > 0) { achados.push(`${tabela}: ${n}`); total += n; }
    }
    console.log(`linhas com prefixo [TESTE]: ${total}${achados.length ? '  (' + achados.join(', ') + ')' : ''}`);

    await c.query('rollback');
  } catch (e) {
    console.log('  ✘ falhou:', String(e.message).replace(/postgres(ql)?:\/\/\S+/g, '<url>'));
  } finally {
    await c.end().catch(() => {});
  }
}
console.log('\nNada foi alterado.');
