/**
 * Cabeçalhos de segurança compartilhados pelos três apps.
 *
 * Escrito em .mjs de propósito: o next.config.ts é lido pelo Node antes
 * de qualquer bundler entrar em ação, então importar TypeScript de outro
 * pacote aqui quebra. JavaScript puro com JSDoc resolve.
 *
 * A CSP começa em report-only, como manda o item 12 da seção 5 do prompt:
 * ela avisa no console o que bloquearia, sem quebrar a página. Quando o
 * relatório vier limpo por alguns dias, troque para modoRelatorio: false.
 */

/**
 * @typedef {Object} Opcoes
 * @property {boolean} [modoRelatorio]  CSP em Content-Security-Policy-Report-Only. Padrão: true.
 */

// O banco (Neon) é falado só pelo servidor — nenhuma origem externa de dado
// precisa ser liberada para o navegador aqui.
const DIRETIVAS_CSP = [
  "default-src 'self'",
  // 'unsafe-inline' e 'unsafe-eval' são necessários para o runtime do Next
  // enquanto não houver nonce por requisição. Reavaliar ao sair do report-only.
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: blob:",
  "connect-src 'self'",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "object-src 'none'",
  "upgrade-insecure-requests",
].join('; ');

/**
 * @param {Opcoes} [opcoes]
 * @returns {{ key: string, value: string }[]}
 */
export function cabecalhosDeSeguranca(opcoes = {}) {
  const modoRelatorio = opcoes.modoRelatorio ?? true;

  return [
    {
      key: modoRelatorio ? 'Content-Security-Policy-Report-Only' : 'Content-Security-Policy',
      value: DIRETIVAS_CSP,
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
