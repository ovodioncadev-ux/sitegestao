import { resolve } from 'node:path';
import { config as carregarEnv } from 'dotenv';
import type { NextConfig } from 'next';
import { cabecalhosDeSeguranca } from '@ovo/config/headers';

// O .env mora na raiz do monorepo, não neste app.
carregarEnv({ path: resolve(process.cwd(), '../../.env') });

// Endereço público do app do assinante: é para lá que "Assinar" leva. Não é segredo.
const URL_ASSINANTE = (process.env.NEXT_PUBLIC_URL_ASSINANTE ?? 'http://localhost:3001').replace(/\/$/, '');

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['@ovo/ui'],
  poweredByHeader: false,
  env: { NEXT_PUBLIC_URL_ASSINANTE: URL_ASSINANTE },
  // A vitrine lê planos, bairros e área de entrega do app do assinante, mas
  // pelo servidor do próprio site: o navegador fala só com a origem do site,
  // sem CORS e sem abrir a CSP (connect-src 'self') para outro domínio.
  async rewrites() {
    return [
      { source: '/api/plans', destination: `${URL_ASSINANTE}/api/plans` },
      { source: '/api/neighborhoods', destination: `${URL_ASSINANTE}/api/neighborhoods` },
      { source: '/api/area', destination: `${URL_ASSINANTE}/api/area` },
      { source: '/api/site', destination: `${URL_ASSINANTE}/api/site` },
    ];
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: cabecalhosDeSeguranca(),
      },
    ];
  },
};

export default nextConfig;
