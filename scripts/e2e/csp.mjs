#!/usr/bin/env node
/**
 * Verifica a política de segurança de conteúdo (CSP) NAS TELAS DE VERDADE.
 *
 * Abre as telas principais dos três apps num navegador, escuta cada violação
 * (evento `securitypolicyviolation`) e mensagem de console da CSP, e LISTA o que a
 * política bloquearia (em modo relatório) ou bloqueou (em modo impor). Sai com
 * código 1 se houver qualquer violação ou erro de página.
 *
 *   SITE=http://localhost:3002 ASSINANTE=http://localhost:3001 GESTAO=http://localhost:3000 \
 *   DATABASE_TEST_URL=... node scripts/e2e/csp.mjs
 *
 * Funciona nos dois modos. Lembre: o modo da CSP é definido no BUILD
 * (CSP_MODO=impor pnpm build). O ideal é rodar nos dois: primeiro em relatório
 * (o que seria bloqueado), depois imposta (nada quebrou).
 *
 * Pré-requisitos: apps no ar com um banco de TESTE migrado, `psql`, Playwright
 * (E2E_PLAYWRIGHT) e Chromium (E2E_CHROMIUM). Cria uma conta [TESTE] e a promove a
 * dono para abrir o painel — só em banco descartável.
 */
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const SITE = process.env.SITE ?? 'http://localhost:3002';
const ASSINANTE = process.env.ASSINANTE ?? 'http://localhost:3001';
const GESTAO = process.env.GESTAO ?? 'http://localhost:3000';
const URL_BANCO = process.env.DATABASE_TEST_URL;
if (!URL_BANCO) throw new Error('Defina DATABASE_TEST_URL (banco de TESTE descartável).');

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.E2E_PLAYWRIGHT ?? 'playwright');
const sql = (q) => execFileSync('psql', [URL_BANCO, '-At', '-c', q], { encoding: 'utf8' }).trim();

const email = `csp-${Date.now()}@exemplo.test`;
const violacoes = new Map(); // chave "diretiva | alvo" → { paginas:Set, disposicao }
const problemas = [];

const navegador = await chromium.launch({ executablePath: process.env.E2E_CHROMIUM, args: ['--no-sandbox'] });
const contexto = await navegador.newContext({ viewport: { width: 1280, height: 900 } });

await contexto.addInitScript(() => {
  window.__csp = [];
  document.addEventListener('securitypolicyviolation', (e) => {
    window.__csp.push({
      diretiva: e.effectiveDirective,
      alvo: e.blockedURI || '(inline)',
      disposicao: e.disposition,
      amostra: (e.sample || '').slice(0, 60),
    });
  });
});

async function visitar(pagina, url, depois) {
  const rotulo = url.replace(/^https?:\/\/[^/]+/, (m) => `[${m.split(':').pop()}]`);
  const consolesCsp = [];
  const aoConsole = (m) => {
    if (/Content Security Policy|Refused to (load|execute|apply|connect)/i.test(m.text())) consolesCsp.push(m.text());
  };
  pagina.on('console', aoConsole);
  try {
    const resposta = await pagina.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
    if (resposta && resposta.status() >= 500) problemas.push(`${rotulo}: a página respondeu HTTP ${resposta.status()}`);
    if (depois) await depois(pagina);
    await pagina.waitForTimeout(400);
    const eventos = await pagina.evaluate(() => window.__csp ?? []);
    for (const ev of eventos) {
      const chave = `${ev.diretiva} | ${ev.alvo}${ev.amostra ? ` | "${ev.amostra}"` : ''}`;
      const atual = violacoes.get(chave) ?? { paginas: new Set(), disposicao: ev.disposicao };
      atual.paginas.add(rotulo);
      violacoes.set(chave, atual);
    }
    for (const texto of consolesCsp) {
      if (!eventos.length) problemas.push(`${rotulo}: ${texto.slice(0, 160)}`);
    }
  } catch (erro) {
    problemas.push(`${rotulo}: ${erro.message.split('\n')[0]}`);
  } finally {
    pagina.off('console', aoConsole);
  }
}

try {
  const pagina = await contexto.newPage();
  pagina.on('pageerror', (e) => problemas.push(`erro de JavaScript na página: ${e.message.slice(0, 140)}`));

  // ── Site ────────────────────────────────────────────────────────────
  await visitar(pagina, `${SITE}/`, async (p) => {
    await p.locator('#entrega').scrollIntoViewIfNeeded();
    await p.fill('input[placeholder="30000-000"]', '30140000'); // dispara a consulta de CEP (connect-src)
    await p.click('text=Conferir');
    await p.waitForTimeout(600);
    // Controle negativo (CSP_CONTROLE=1): injeta de propósito uma imagem externa, que a
    // política proíbe, para provar que este verificador de fato enxerga violações.
    if (process.env.CSP_CONTROLE) {
      await p.evaluate(() => {
        const img = document.createElement('img');
        img.src = 'https://externo.exemplo.invalid/pixel.png';
        document.body.appendChild(img);
      });
      await p.waitForTimeout(300);
    }
  });

  // ── Assinante: público ─────────────────────────────────────────────
  for (const caminho of ['/entrar', '/cadastro', '/assinar', '/assinar?plano=semanal']) {
    await visitar(pagina, `${ASSINANTE}${caminho}`);
  }

  // ── Assinante: logado ──────────────────────────────────────────────
  const cadastro = await pagina.request.post(`${ASSINANTE}/api/auth/sign-up/email`, {
    data: { name: '[TESTE] CSP', email, password: 'senha-csp-segura-12345' },
    headers: { origin: ASSINANTE },
  });
  if (!cadastro.ok()) throw new Error(`não consegui criar a conta de teste (HTTP ${cadastro.status()})`);
  for (const caminho of ['/', '/dados', '/assinar?plano=semanal']) {
    await visitar(pagina, `${ASSINANTE}${caminho}`);
  }

  // ── Gestão (a mesma conta, promovida a dono; o cookie vale entre as portas do localhost) ──
  sql(`update perfis set papel = 'dono' where id = (select id from "user" where email = '${email}')`);
  await visitar(pagina, `${GESTAO}/entrar`);
  for (const caminho of ['/', '/clientes', '/assinaturas', '/entregas', '/faturas', '/area-de-entrega', '/interessados', '/faq', '/configuracoes', '/historico']) {
    await visitar(pagina, `${GESTAO}${caminho}`);
  }
} catch (erro) {
  problemas.push(erro.message);
} finally {
  await navegador.close();
}

const lista = [...violacoes.entries()];
const imposta = lista.some(([, v]) => v.disposicao === 'enforce');
console.log(`\nCSP — violações distintas: ${lista.length}${lista.length ? (imposta ? ' (BLOQUEADAS)' : ' (seriam bloqueadas; modo relatório)') : ''}`);
for (const [chave, v] of lista) console.log(`  ✘ ${chave}\n      em: ${[...v.paginas].join(', ')}`);
for (const p of problemas) console.log(`  ✘ ${p}`);

if (lista.length || problemas.length) {
  console.error('\n✘ A CSP não está limpa nas telas principais.');
  process.exit(1);
}
console.log('✔ Nenhuma violação de CSP nas telas principais dos três apps.');
