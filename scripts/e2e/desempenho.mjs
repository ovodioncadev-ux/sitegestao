#!/usr/bin/env node
/**
 * Medidor de desempenho do SITE (métricas de laboratório) com ORÇAMENTO.
 *
 * Abre a página inicial num Chromium com rede e CPU limitadas (rede ~"4G rápida",
 * CPU 4× mais lenta) e mede: LCP, CLS, JavaScript transferido, nº de requisições,
 * tamanho do HTML e se o conteúdo principal já vem no HTML (o que o buscador vê).
 * Sai com código 1 se algum orçamento for estourado.
 *
 *   SITE=http://localhost:3002 node scripts/e2e/desempenho.mjs
 *
 * ATENÇÃO: é medição de LABORATÓRIO contra o endereço informado. Em localhost não há
 * latência de internet nem CDN, então os números absolutos são otimistas; valem para
 * COMPARAR antes/depois e para pegar regressão. Meça também contra o ambiente real.
 *
 * Pré-requisitos: Playwright (E2E_PLAYWRIGHT) e Chromium (E2E_CHROMIUM).
 */
import { createRequire } from 'node:module';

const SITE = (process.env.SITE ?? 'http://localhost:3002').replace(/\/$/, '');
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.E2E_PLAYWRIGHT ?? 'playwright');

// Orçamento (ajustável por variável de ambiente).
const ORCAMENTO = {
  lcpMs: Number(process.env.ORC_LCP_MS ?? 2500),
  cls: Number(process.env.ORC_CLS ?? 0.1),
  jsKb: Number(process.env.ORC_JS_KB ?? 150),
  requisicoes: Number(process.env.ORC_REQ ?? 25),
};

/** Texto que PRECISA estar no HTML cru para o buscador indexar. */
const NO_HTML = process.env.HTML_DEVE_CONTER
  ? process.env.HTML_DEVE_CONTER.split('|')
  : ['Ovos caipiras, da fazenda', 'Escolher Semanal', 'Como assino?'];
/** E isto NÃO pode estar (estado de carregamento no HTML = conteúdo ausente). */
const FORA_DO_HTML = ['Carregando planos', 'Carregando perguntas', 'Carregando bairros'];

const navegador = await chromium.launch({ executablePath: process.env.E2E_CHROMIUM, args: ['--no-sandbox'] });
const contexto = await navegador.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
const pagina = await contexto.newPage();

const cdp = await contexto.newCDPSession(pagina);
await cdp.send('Network.enable');
await cdp.send('Network.emulateNetworkConditions', {
  offline: false,
  latency: 150,
  downloadThroughput: (1.6 * 1024 * 1024) / 8,
  uploadThroughput: (750 * 1024) / 8,
});
await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });

await pagina.addInitScript(() => {
  window.__metricas = { lcp: 0, cls: 0 };
  new PerformanceObserver((lista) => {
    for (const e of lista.getEntries()) window.__metricas.lcp = e.startTime;
  }).observe({ type: 'largest-contentful-paint', buffered: true });
  new PerformanceObserver((lista) => {
    for (const e of lista.getEntries()) if (!e.hadRecentInput) window.__metricas.cls += e.value;
  }).observe({ type: 'layout-shift', buffered: true });
});

const erros = [];
pagina.on('pageerror', (e) => erros.push(e.message.slice(0, 120)));
pagina.on('console', (m) => {
  if (m.type() === 'error') erros.push(m.text().slice(0, 120));
});

let htmlCru = '';
let totalHtml = 0;
pagina.on('response', async (r) => {
  if (r.url() === `${SITE}/` || r.url() === SITE) {
    try {
      htmlCru = await r.text();
      totalHtml = Buffer.byteLength(htmlCru);
    } catch {
      /* resposta já descartada */
    }
  }
});

await pagina.goto(SITE, { waitUntil: 'networkidle', timeout: 60000 });
await pagina.waitForTimeout(1500);

const medido = await pagina.evaluate(() => {
  const recursos = performance.getEntriesByType('resource');
  const js = recursos.filter((r) => r.initiatorType === 'script' || /\.js(\?|$)/.test(r.name));
  const nav = performance.getEntriesByType('navigation')[0];
  return {
    lcp: window.__metricas.lcp,
    cls: window.__metricas.cls,
    jsBytes: js.reduce((s, r) => s + (r.transferSize || r.encodedBodySize || 0), 0),
    requisicoes: recursos.length + 1,
    ttfb: nav ? nav.responseStart : 0,
  };
});
await navegador.close();

const jsKb = medido.jsBytes / 1024;
let falhas = 0;
const linha = (ok, texto) => {
  if (!ok) falhas += 1;
  console.log(`  ${ok ? '✔' : '✘'} ${texto}`);
};

console.log(`\nDesempenho (laboratório, rede ~4G + CPU 4× mais lenta, celular 390px) — ${SITE}`);
console.log(`  TTFB ${medido.ttfb.toFixed(0)} ms · HTML ${(totalHtml / 1024).toFixed(1)} KB · ${medido.requisicoes} requisições`);
linha(medido.lcp > 0 && medido.lcp <= ORCAMENTO.lcpMs, `LCP ${medido.lcp.toFixed(0)} ms (orçamento ${ORCAMENTO.lcpMs} ms)`);
linha(medido.cls <= ORCAMENTO.cls, `CLS ${medido.cls.toFixed(3)} (orçamento ${ORCAMENTO.cls})`);
linha(jsKb <= ORCAMENTO.jsKb, `JavaScript transferido ${jsKb.toFixed(1)} KB (orçamento ${ORCAMENTO.jsKb} KB)`);
linha(medido.requisicoes <= ORCAMENTO.requisicoes, `${medido.requisicoes} requisições (orçamento ${ORCAMENTO.requisicoes})`);

for (const trecho of NO_HTML) linha(htmlCru.includes(trecho), `no HTML cru (buscador): "${trecho}"`);
for (const trecho of FORA_DO_HTML) linha(!htmlCru.includes(trecho), `HTML cru NÃO tem o estado "${trecho}"`);
linha(erros.length === 0, erros.length === 0 ? 'sem erros no console' : `erros no console: ${erros.slice(0, 2).join(' | ')}`);

if (falhas > 0) {
  console.error(`\n✘ ${falhas} item(ns) fora do orçamento.`);
  process.exit(1);
}
console.log('\n✔ Dentro do orçamento.');
