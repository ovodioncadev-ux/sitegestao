/**
 * Cabeçalhos de segurança compartilhados pelos três apps.
 *
 * Escrito em .mjs de propósito: o next.config.ts é lido pelo Node antes
 * de qualquer bundler entrar em ação, então importar TypeScript de outro
 * pacote aqui quebra. JavaScript puro com JSDoc resolve.
 *
 * A CSP começa em report-only: ela avisa no console o que bloquearia, sem
 * quebrar a página. O modo vem de CSP_MODO (relatorio | impor); sem a variável,
 * continua em relatório — nada muda sozinho. Para IMPOR, defina CSP_MODO=impor
 * no ambiente (scripts/e2e/csp.mjs prova que as telas principais não violam a política).
 */

/**
 * @typedef {Object} Opcoes
 * @property {boolean} [modoRelatorio]  CSP em Content-Security-Policy-Report-Only. Padrão: true, salvo CSP_MODO=impor.
 */

// O banco (Neon) é falado só pelo servidor — nenhuma origem externa de dado
// precisa ser liberada para o navegador aqui.
/**
 * `upgrade-insecure-requests` só vale quando a política é IMPOSTA: no
 * desenvolvimento (http://localhost) ele reescreveria as chamadas para https e
 * quebraria tudo, e em relatório ele nem é aplicado.
 */
function diretivasCsp(imposta) {
  return [
  "default-src 'self'",
  // 'unsafe-inline' e 'unsafe-eval' são necessários para o runtime do Next
  // enquanto não houver nonce por requisição. Reavaliar ao sair do report-only.
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  // As fontes são servidas pelo próprio app (next/font): nenhum domínio externo.
  "style-src 'self' 'unsafe-inline'",
  "font-src 'self'",
  "img-src 'self' data: blob:",
  "connect-src 'self'",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
  ...(imposta ? ["upgrade-insecure-requests"] : []),
  ].join('; ');
}

/**
 * @param {Opcoes} [opcoes]
 * @returns {{ key: string, value: string }[]}
 */
export function cabecalhosDeSeguranca(opcoes = {}) {
  const modoRelatorio = opcoes.modoRelatorio ?? process.env.CSP_MODO !== 'impor';

  return [
    {
      key: modoRelatorio ? 'Content-Security-Policy-Report-Only' : 'Content-Security-Policy',
      value: diretivasCsp(!modoRelatorio),
    },
    {
      // HTTPS forçado por dois anos, incluindo subdomínios.
      key: 'Strict-Transport-Security',
      value: 'max-age=63072000; includeSubDomains; preload',
    },
    { key: 'X-Content-Type-Options', value: 'nosniff' },
    { key: 'X-Frame-Options', value: 'DENY' },
    { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
    {
      key: 'Permissions-Policy',
      value: 'camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()',
    },
    { key: 'X-DNS-Prefetch-Control', value: 'off' },
  ];
}
