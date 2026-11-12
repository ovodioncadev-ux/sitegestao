#!/usr/bin/env node
/**
 * PRÉVIA da limpeza de [TESTE] no banco PRINCIPAL. SOMENTE LEITURA
 * (begin read only + rollback). Não apaga nada.
 *
 *   node packages/database/scripts/previa-teste.mjs
 */
import pg from 'pg';
import { carregarEnv } from './banco-teste.mjs';

carregarEnv();
const url = process.env.DATABASE_ADMIN_URL;
if (!url) { console.log('DATABASE_ADMIN_URL ausente no .env'); process.exit(1); }

const c = new pg.Client({ connectionString: url, connectionTimeoutMillis: 20000 });
try {
  await c.connect();
  await c.query('begin read only');

  const contas = await c.query(
    `select id, email, name from "user"
      where email like '%@ovo-teste.test' or name like '[TESTE]%' order by email`);
  console.log(`\n── Contas de teste (${contas.rows.length}) ──`);
  console.table(contas.rows);

  const clientes = await c.query(
    `select nome, email from clientes
      where nome like '[TESTE]%' or email like '%@ovo-teste.test' order by nome`);
  console.log(`── Clientes de teste (${clientes.rows.length}) ──`);
  console.table(clientes.rows);

  const faixas = await c.query(`select bairro from faixas_cep_atendidas where bairro like '[TESTE]%'`);
  console.log(`── Faixas de CEP de teste (${faixas.rows.length}) ──`);
  console.table(faixas.rows);

  await c.query('rollback');
} catch (e) {
  console.log('✘', String(e.message).replace(/postgres(ql)?:\/\/\S+/g, '<url>'));
  process.exitCode = 1;
} finally {
  await c.end().catch(() => {});
}
console.log('Nada foi alterado.');
