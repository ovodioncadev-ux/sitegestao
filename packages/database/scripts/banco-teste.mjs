/**
 * Guarda do banco de testes. Usada por `rodar-sql.mjs` e `migrar-teste.mjs`.
 *
 * Regra: teste e migration de teste SÓ rodam em `DATABASE_TEST_URL` (um branch
 * do Neon separado). Não existe fallback para `DATABASE_ADMIN_URL`: sem a
 * variável, ou com ela apontando para o banco principal, o processo aborta.
 * Nenhuma mensagem imprime a URL, só o nome da variável.
 */

import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
export const raizMonorepo = resolve(aqui, '../../..');

export function carregarEnv() {
  for (const arquivo of ['.env', '.env.local']) {
    const caminho = resolve(raizMonorepo, arquivo);
    if (!existsSync(caminho)) continue;
    for (const linha of readFileSync(caminho, 'utf8').split('\n')) {
      const m = linha.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
      if (!m) continue;
      if (!(m[1] in process.env)) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
  }
}

/** "host/banco" sem o sufixo -pooler: a conexão direta e a do pooler são o mesmo banco. */
export function identidade(url) {
  const u = new URL(url);
  return `${u.hostname.replace('-pooler', '')}/${u.pathname.slice(1)}`.toLowerCase();
}

/**
 * Devolve `{ ok: true }` ou `{ ok: false, motivo }`. Pura, para poder ser testada
 * sem banco. `principais` são as URLs do banco principal (ADMIN e DATABASE_URL).
 * @param {string | undefined | null} urlTeste
 * @param {(string | undefined | null)[]} principais
 * @returns {{ ok: boolean, motivo?: string }}
 */
export function validarBancoDeTeste(urlTeste, principais) {
  if (!urlTeste) {
    return {
      ok: false,
      motivo:
        'DATABASE_TEST_URL não está configurada. Os testes não rodam mais no banco principal.\n' +
        '  1. No Neon, crie um branch de teste (ex.: "teste") e copie a connection string dele.\n' +
        '  2. Coloque no .env da raiz: DATABASE_TEST_URL=<connection string do branch>\n' +
        '  3. Aplique as migrations nele: pnpm db:migrar:teste\n' +
        '  Detalhes: README.md, seção "Banco de testes".',
    };
  }
  let alvo;
  try {
    alvo = identidade(urlTeste);
  } catch {
    return { ok: false, motivo: 'DATABASE_TEST_URL não é uma connection string válida (postgresql://...).' };
  }
  for (const p of principais) {
    if (!p) continue;
    try {
      if (identidade(p) === alvo) {
        return {
          ok: false,
          motivo:
            'DATABASE_TEST_URL aponta para o MESMO banco do DATABASE_URL/DATABASE_ADMIN_URL. ' +
            'Aponte-a para o branch de teste do Neon. Abortado para não tocar no banco principal.',
        };
      }
    } catch {
      /* URL principal ilegível: não é problema desta checagem */
    }
  }
  return { ok: true };
}

/** Carrega o .env, valida e devolve a URL de teste. Aborta o processo com exit 1 se não puder. */
export function urlDoBancoDeTeste() {
  carregarEnv();
  const r = validarBancoDeTeste(process.env.DATABASE_TEST_URL, [
    process.env.DATABASE_ADMIN_URL,
    process.env.DATABASE_URL,
  ]);
  if (!r.ok) {
    console.error('');
    console.error(`✘ ${r.motivo}`);
    process.exit(1);
  }
  return process.env.DATABASE_TEST_URL;
}
