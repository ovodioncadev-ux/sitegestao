import { resolve } from 'node:path';
import { config as carregarEnv } from 'dotenv';
import type { NextConfig } from 'next';
import { cabecalhosDeSeguranca } from '@ovo/config/headers';

// O .env mora na raiz do monorepo, não neste app.
carregarEnv({ path: resolve(process.cwd(), '../../.env') });

const nextConfig: NextConfig = {
  reactStrictMode: true,
  transpilePackages: ['@ovo/ui'],
  poweredByHeader: false,
  // Em produção o vercel.json manda /conta/* e /gestao/* para os outros apps.
  // No dev local (cada app na sua porta) o rewrite abaixo faz o mesmo, pelo
  // servidor do site: o navegador fala só com a origem do site, sem CORS.
  async rewrites() {
    if (process.env.NODE_ENV === 'production') return [];
    return [
      { source: '/conta/:path*', destination: 'http://localhost:3001/conta/:path*' },
      { source: '/gestao/:path*', destination: 'http://localhost:3000/gestao/:path*' },
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
