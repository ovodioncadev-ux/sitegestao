#!/usr/bin/env node
/**
 * Roda um arquivo .sql contra o banco e imprime os avisos.
 *
 * Existe para não depender do `psql` instalado no Windows — o Node e a
 * biblioteca `pg` já estão no projeto. Se o script terminar com erro, o
 * processo sai com código 1, que é o que o CI observa.
 *
 *   node scripts/rodar-sql.mjs tests/teste-autorizacao.sql
 */

import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { carregarEnv, urlDoBancoDeTeste } from './banco-teste.mjs';

const aqui = dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const noPrincipal = args.includes('--banco-principal');
const caminhoSql = args.find((a) => !a.startsWith('--'));
if (!caminhoSql) {
  console.error('Uso: node scripts/rodar-sql.mjs <arquivo.sql>');
  process.exit(1);
}

// Testes SÓ rodam em DATABASE_TEST_URL (branch de teste do Neon). Não há
// fallback para o banco principal: sem a variável, o processo aborta.
// Única exceção, explícita: manutenção em scripts/ (ex.: db:limpar-teste),
// que passa --banco-principal. Arquivos de tests/ nunca podem usar a exceção.
let url;
if (noPrincipal) {
  if (!caminhoSql.startsWith('scripts/')) {
    console.error('✘ --banco-principal só vale para arquivos em scripts/. Testes (tests/) rodam apenas em DATABASE_TEST_URL.');
    process.exit(1);
  }
  carregarEnv();
  url = process.env.DATABASE_ADMIN_URL;
  if (!url) {
    console.error('Falta DATABASE_ADMIN_URL no .env da raiz do monorepo.');
    process.exit(1);
  }
  console.warn('⚠ Rodando no BANCO PRINCIPAL (manutenção explícita, --banco-principal).');
} else {
  url = urlDoBancoDeTeste();
}

const sql = readFileSync(resolve(aqui, '..', caminhoSql), 'utf8');
const cliente = new pg.Client({ connectionString: url });

cliente.on('notice', (aviso) => {
  const texto = (aviso.message ?? '').replace(/\s+$/, '');
  if (texto) console.log(texto);
});

try {
  await cliente.connect();
  await cliente.query(sql);
  console.log('');
  process.exitCode = 0;
} catch (erro) {
  console.error('');
  console.error(`✘ ${erro.message}`);
  process.exitCode = 1;
} finally {
  await cliente.end().catch(() => {});
}
