#!/usr/bin/env node
/**
 * Prova a ATOMICIDADE de consumir_rate_limit com conexões simultâneas de verdade.
 *
 * Cenário 1 — mesma chave: N tentativas ao mesmo tempo, cada uma em sua conexão, contra o
 * MESMO limite (max). Se verificar e incrementar fossem passos separados (ler → decidir →
 * gravar), várias passariam pela leitura "velha" e o total de permitidas passaria de `max`.
 * Aqui precisa ser EXATAMENTE `max`.
 *
 * Cenário 2 — com linhas VENCIDAS no banco: o gatilho da tabela apaga linhas vencidas a cada
 * escrita. Centenas de escritas simultâneas disputando as mesmas linhas vencidas poderiam
 * travar (deadlock) ou falhar. Semeia linhas vencidas, dispara várias chaves em paralelo e exige:
 * nenhum erro, e exatamente `max` permitidas POR chave. Repete algumas rodadas.
 *
 *   pnpm --filter @ovo/database teste:concorrencia
 *
 * Só roda no banco de teste (DATABASE_TEST_URL). Limpa o que criou.
 */
import pg from 'pg';
import { urlDoBancoDeTeste } from './banco-teste.mjs';

const pool = new pg.Pool({ connectionString: urlDoBancoDeTeste(), max: 40 });
const prefixo = `teste-concorrencia-${Date.now()}`;
let falhou = false;
const falha = (msg) => {
  falhou = true;
  console.error(`✘ ${msg}`);
};

const consumir = (chave, max) =>
  pool.query('select permitido from consumir_rate_limit($1, $2, 60)', [chave, max]).then((r) => r.rows[0].permitido);

try {
  // ── Cenário 1: mesma chave ────────────────────────────────────────────
  {
    const MAX = 10;
    const TENTATIVAS = 60;
    const chave = `${prefixo}-mesma`;
    const resultados = await Promise.all(Array.from({ length: TENTATIVAS }, () => consumir(chave, MAX)));
    const permitidas = resultados.filter(Boolean).length;
    const contador = (await pool.query("select count from rateLimit where ip = $1 and endpoint = 'auth'", [chave])).rows[0]?.count;
    if (permitidas === MAX && contador === TENTATIVAS) {
      console.log(`  OK  mesma chave: ${TENTATIVAS} tentativas simultâneas, limite ${MAX}: exatamente ${permitidas} passaram; contador = ${contador}`);
    } else {
      falha(`mesma chave: passaram ${permitidas} (esperado ${MAX}); contador ${contador} (esperado ${TENTATIVAS})`);
    }
  }

  // ── Cenário 2: linhas vencidas + várias chaves em paralelo ────────────
  const RODADAS = 5;
  const CHAVES = 20;
  const POR_CHAVE = 12;
  const MAX = 5;
  for (let rodada = 1; rodada <= RODADAS; rodada++) {
    // 400 linhas vencidas que o gatilho de limpeza vai disputar.
    await pool.query(
      `insert into rateLimit (ip, endpoint, count, reset_at)
       select $1 || '-vencida-' || g, 'auth', 3, now() - interval '5 minutes'
         from generate_series(1, 400) g
       on conflict do nothing`,
      [prefixo],
    );
    // Algumas chaves "ativas" já vencidas também: a janela delas tem de reiniciar em 1.
    const chaves = Array.from({ length: CHAVES }, (_, i) => `${prefixo}-r${rodada}-k${i}`);
    await pool.query(
      `insert into rateLimit (ip, endpoint, count, reset_at)
       select k, 'auth', 99, now() - interval '1 second' from unnest($1::text[]) k on conflict do nothing`,
      [chaves.slice(0, 5)],
    );

    const tarefas = chaves.flatMap((chave) => Array.from({ length: POR_CHAVE }, () => consumir(chave, MAX).then((p) => [chave, p])));
    const resultados = await Promise.allSettled(tarefas);

    const rejeitadas = resultados.filter((r) => r.status === 'rejected');
    if (rejeitadas.length > 0) {
      falha(`rodada ${rodada}: ${rejeitadas.length} chamadas falharam (ex.: ${rejeitadas[0].reason?.message ?? rejeitadas[0].reason})`);
      continue;
    }
    const porChave = new Map();
    for (const r of resultados) {
      const [chave, permitido] = r.value;
      porChave.set(chave, (porChave.get(chave) ?? 0) + (permitido ? 1 : 0));
    }
    const erradas = [...porChave].filter(([, n]) => n !== MAX);
    if (erradas.length > 0) {
      falha(`rodada ${rodada}: ${erradas.length} chave(s) com permitidas ≠ ${MAX} (ex.: ${erradas[0][1]})`);
    } else {
      console.log(`  OK  rodada ${rodada}/${RODADAS}: ${CHAVES * POR_CHAVE} chamadas em ${CHAVES} chaves com linhas vencidas no banco: sem erro, exatamente ${MAX} por chave`);
    }
  }
} finally {
  await pool.query("delete from rateLimit where endpoint = 'auth' and ip like $1", [`${prefixo}%`]).catch(() => {});
  await pool.end();
}
process.exit(falhou ? 1 : 0);
