#!/usr/bin/env node
/**
 * Teste de fumaça: roda contra apps JÁ NO AR (local, CI ou produção) e confere o
 * que um VISITANTE ANÔNIMO enxerga — o que deve responder, o que deve se recusar
 * e o que nunca pode aparecer.
 *
 *   SITE=https://exemplo.com.br ASSINANTE=https://app.exemplo.com.br \
 *   GESTAO=https://gestao.exemplo.com.br node scripts/smoke.mjs
 *
 * Defina só os que existem (ao menos um). NÃO ESCREVE NADA: só GETs e POSTs com corpo
 * inválido de propósito (recusados por validação, sem efeito). Em particular, a sonda de
 * cadastro do painel usa dados inválidos para que, mesmo que a guarda regrida, nenhuma conta
 * seja criada em produção. Sai com código 1 se qualquer verificação falhar. Use depois de CADA deploy.
 */

const ALVOS = {
  site: process.env.SITE,
  assinante: process.env.ASSINANTE,
  gestao: process.env.GESTAO,
};
const definidos = Object.entries(ALVOS).filter(([, url]) => url);
if (definidos.length === 0) {
  console.error('Defina ao menos um: SITE, ASSINANTE ou GESTAO (URL base, sem barra no fim).');
  process.exit(2);
}

let falhas = 0;
let total = 0;
const ok = (texto) => console.log(`  ✔ ${texto}`);
function conferir(condicao, texto, detalhe = '') {
  total += 1;
  if (condicao) return ok(texto);
  falhas += 1;
  console.error(`  ✘ ${texto}${detalhe ? ` — ${detalhe}` : ''}`);
}

/** Nada disto pode aparecer em NENHUMA resposta pública. */
const PROIBIDO = [
  [/postgres(ql)?:\/\//i, 'URL de banco'],
  [/DATABASE_(ADMIN_|TEST_)?URL/, 'nome de variável de banco'],
  [/BETTER_AUTH_SECRET|CRON_SECRET|APP_SERVIDOR_SENHA|PAGAMENTO_SIMULADO_SEGREDO/, 'nome de segredo'],
  [/node_modules\/|\bat (async )?[A-Za-z_.]+ \(.*:\d+:\d+\)/, 'stack trace'],
];

async function pegar(base, caminho, opcoes = {}) {
  let res;
  try {
    res = await fetch(base + caminho, { redirect: 'manual', signal: AbortSignal.timeout(15000), ...opcoes });
  } catch (erro) {
    throw new Error(`sem resposta de ${base}${caminho} (${erro?.cause?.code ?? erro?.name ?? 'erro de rede'})`);
  }
  const texto = await res.text();
  return { res, texto };
}

function semVazamento(rotulo, texto) {
  for (const [padrao, nome] of PROIBIDO) {
    conferir(!padrao.test(texto), `${rotulo}: sem ${nome} na resposta`);
  }
}

function cabecalhosDeSeguranca(rotulo, res) {
  const h = (n) => res.headers.get(n) ?? '';
  conferir(/max-age=\d{6,}/.test(h('strict-transport-security')), `${rotulo}: HSTS`);
  conferir(h('x-content-type-options') === 'nosniff', `${rotulo}: X-Content-Type-Options: nosniff`);
  conferir(h('x-frame-options').toUpperCase() === 'DENY', `${rotulo}: X-Frame-Options: DENY`);
  conferir(
    Boolean(h('content-security-policy') || h('content-security-policy-report-only')),
    `${rotulo}: tem política de segurança de conteúdo (CSP)`,
  );
  conferir(h('x-powered-by') === '', `${rotulo}: não anuncia a tecnologia (X-Powered-By)`);
}

/** Redirecionamento para o login, nunca conteúdo. */
function mandaParaLogin(rotulo, res, texto) {
  const destino = res.headers.get('location') ?? '';
  conferir(
    [301, 302, 303, 307, 308].includes(res.status) && /\/entrar/.test(destino),
    `${rotulo}: visitante sem login é mandado para /entrar`,
    `HTTP ${res.status} → ${destino || '(sem Location)'}`,
  );
  conferir(!/Painel do dono|Minha assinatura|Olá,/.test(texto), `${rotulo}: não vaza conteúdo da área logada`);
}

async function saude(rotulo, base) {
  const { res, texto } = await pegar(base, '/api/saude');
  let corpo = null;
  try {
    corpo = JSON.parse(texto);
  } catch {
    /* tratado abaixo */
  }
  conferir(res.status === 200 && corpo?.ok === true, `${rotulo}: /api/saude responde { ok: true }`, `HTTP ${res.status}`);
  conferir(Object.keys(corpo ?? {}).join() === 'ok', `${rotulo}: /api/saude devolve só "ok" (sem detalhe)`);
}

async function jsonDe(rotulo, base, caminho, validar, descricao) {
  const { res, texto } = await pegar(base, caminho);
  let corpo = null;
  try {
    corpo = JSON.parse(texto);
  } catch {
    /* tratado abaixo */
  }
  conferir(res.status === 200 && corpo !== null && validar(corpo), `${rotulo}: ${caminho} ${descricao}`, `HTTP ${res.status}`);
  semVazamento(`${rotulo} ${caminho}`, texto);
}

try {
  // ── Site ───────────────────────────────────────────────────────────────
  if (ALVOS.site) {
    const base = ALVOS.site.replace(/\/$/, '');
    console.log(`\nSite  ${base}`);
    const { res, texto } = await pegar(base, '/');
    conferir(res.status === 200 && /<html[^>]*lang="pt-BR"/.test(texto), 'site: / responde 200 com a página em pt-BR', `HTTP ${res.status}`);
    cabecalhosDeSeguranca('site /', res);
    semVazamento('site /', texto);
    await saude('site', base);
    await jsonDe('site', base, '/api/plans', (c) => Array.isArray(c.planos) && c.planos.length > 0, 'devolve os planos');
    await jsonDe('site', base, '/api/site', (c) => Array.isArray(c.faq), 'devolve o conteúdo (FAQ)');
  }

  // ── Assinante ──────────────────────────────────────────────────────────
  if (ALVOS.assinante) {
    const base = ALVOS.assinante.replace(/\/$/, '');
    console.log(`\nAssinante  ${base}`);
    await saude('assinante', base);
    await jsonDe('assinante', base, '/api/plans', (c) => Array.isArray(c.planos) && c.planos.length > 0, 'devolve os planos');
    await jsonDe('assinante', base, '/api/neighborhoods', (c) => Array.isArray(c.bairros), 'devolve a lista de bairros');

    const entrar = await pegar(base, '/entrar');
    conferir(entrar.res.status === 200, 'assinante: /entrar responde 200', `HTTP ${entrar.res.status}`);
    cabecalhosDeSeguranca('assinante /entrar', entrar.res);
    semVazamento('assinante /entrar', entrar.texto);

    const home = await pegar(base, '/');
    mandaParaLogin('assinante /', home.res, home.texto);

    const area = await pegar(base, '/api/area?cep=abc');
    conferir(area.res.status === 400, 'assinante: /api/area recusa CEP inválido (400)', `HTTP ${area.res.status}`);

    const evento = await pegar(base, '/api/evento', { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } });
    conferir(evento.res.status === 400, 'assinante: /api/evento recusa evento inválido (400)', `HTTP ${evento.res.status}`);

    const interesse = await pegar(base, '/api/interesse', { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } });
    conferir(interesse.res.status === 400, 'assinante: /api/interesse recusa pedido sem consentimento (400)', `HTTP ${interesse.res.status}`);

    const webhook = await pegar(base, '/api/pagamento/webhook', { method: 'POST', body: '{}', headers: { 'content-type': 'application/json' } });
    conferir([400, 404].includes(webhook.res.status), 'assinante: webhook de pagamento recusa aviso vazio (400) ou está desligado (404)', `HTTP ${webhook.res.status}`);
    semVazamento('assinante webhook', webhook.texto);

    const simulado = await pegar(base, '/pagamento/simulado/3f1c2a52-8b6e-4c3a-9d3e-1a2b3c4d5e6f?valor=100');
    conferir(simulado.res.status === 404, 'assinante: o simulador de pagamento NÃO existe aqui (404)', `HTTP ${simulado.res.status}`);
  }

  // ── Gestão ─────────────────────────────────────────────────────────────
  if (ALVOS.gestao) {
    const base = ALVOS.gestao.replace(/\/$/, '');
    console.log(`\nGestão  ${base}`);
    await saude('gestao', base);

    const entrar = await pegar(base, '/entrar');
    conferir(entrar.res.status === 200, 'gestão: /entrar responde 200', `HTTP ${entrar.res.status}`);
    cabecalhosDeSeguranca('gestão /entrar', entrar.res);
    semVazamento('gestão /entrar', entrar.texto);

    for (const caminho of ['/', '/clientes', '/faturas', '/interessados', '/interessados/exportar', '/configuracoes']) {
      const { res, texto } = await pegar(base, caminho);
      mandaParaLogin(`gestão ${caminho}`, res, texto);
    }

    const rotina = await pegar(base, '/api/rotina', { method: 'POST' });
    conferir(rotina.res.status === 401, 'gestão: /api/rotina sem segredo é recusada (401)', `HTTP ${rotina.res.status}`);
    const rotinaErrada = await pegar(base, '/api/rotina', { method: 'POST', headers: { authorization: 'Bearer segredo-errado' } });
    conferir(rotinaErrada.res.status === 401, 'gestão: /api/rotina com segredo errado é recusada (401)', `HTTP ${rotinaErrada.res.status}`);

    // Sonda SEGURA: o corpo é INVÁLIDO de propósito (senha curta demais, e-mail sem domínio).
    // Com a guarda do painel, a rota nem existe (404). Se a guarda um dia regredir, a rota
    // existiria mas recusaria a validação (400/422) — e NENHUMA conta seria criada. Um corpo
    // válido aqui faria este teste, rodando em produção, criar um usuário de verdade.
    const cadastro = await pegar(base, '/api/auth/sign-up/email', {
      method: 'POST',
      headers: { 'content-type': 'application/json', origin: base },
      body: JSON.stringify({ name: 'x', email: 'invalido', password: 'curta' }),
    });
    conferir(cadastro.res.status === 404, 'gestão: cadastro público de conta no painel NÃO existe (404)', `HTTP ${cadastro.res.status}`);
  }

} catch (erro) {
  console.error(`\n✘ ${erro.message}`);
  process.exit(1);
}

console.log(`\n${total - falhas} de ${total} verificações passaram.`);
if (falhas > 0) {
  console.error(`✘ ${falhas} falha(s) no teste de fumaça.`);
  process.exit(1);
}
console.log('✔ Teste de fumaça limpo.');
