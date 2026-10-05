#!/usr/bin/env node
/**
 * Prova a ATOMICIDADE de consumir_rate_limit com conexões simultâneas de verdade.
 *
 * Dispara N tentativas ao mesmo tempo, cada uma em sua própria conexão, contra o
 * MESMO limite (max). Se a verificação e o incremento fossem passos separados
 * (ler → decidir → gravar), várias passariam pela leitura "velha" e o número de
 * permitidas passaria de `max`. Aqui precisa ser EXATAMENTE `max`.
 *
 *   pnpm --filter @ovo/database teste:concorrencia
 *
 * Só roda no banco de teste (DATABASE_TEST_URL). Limpa a chave que usou.
 */
import pg from 'pg';
import { urlDoBancoDeTeste } from './banco-teste.mjs';

const MAX = 10;
const TENTATIVAS = 60;
const chave = `teste-concorrencia-${Date.now()}`;

const pool = new pg.Pool({ connectionString: urlDoBancoDeTeste(), max: 30 });
let falhou = false;
try {
  const resultados = await Promise.all(
    Array.from({ length: TENTATIVAS }, () =>
      pool.query('select permitido from consumir_rate_limit($1, $2, 60)', [chave, MAX]).then((r) => r.rows[0].permitido),
    ),
  );
  const permitidas = resultados.filter(Boolean).length;
  const contador = (await pool.query("select count from rateLimit where ip = $1 and endpoint = 'auth'", [chave])).rows[0]?.count;

  if (permitidas === MAX && contador === TENTATIVAS) {
    console.log(`  OK  ${TENTATIVAS} tentativas simultâneas, limite ${MAX}: exatamente ${permitidas} passaram; contador = ${contador}`);
  } else {
    falhou = true;
    console.error(`✘ ${TENTATIVAS} tentativas simultâneas com limite ${MAX}: passaram ${permitidas} (esperado ${MAX}); contador ${contador} (esperado ${TENTATIVAS})`);
  }
} finally {
  await pool.query("delete from rateLimit where ip = $1 and endpoint = 'auth'", [chave]).catch(() => {});
  await pool.end();
}
process.exit(falhou ? 1 : 0);
