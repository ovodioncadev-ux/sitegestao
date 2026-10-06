import { resolve } from 'node:path';
import { config as carregarEnv } from 'dotenv';
import type { NextConfig } from 'next';
import { cabecalhosDeSeguranca } from '@ovo/config/headers';

// O .env mora na raiz do monorepo, não neste app — o Next só carrega .env
// do próprio diretório por padrão.
carregarEnv({ path: resolve(process.cwd(), '../../.env') });

const nextConfig: NextConfig = {
  reactStrictMode: true,
  // Os pacotes do monorepo são TypeScript cru, compilados pelo próprio Next.
  transpilePackages: ['@ovo/database', '@ovo/ui'],
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: '/:path*',
        // O modo da CSP vem de CSP_MODO (relatorio | impor), lido NO BUILD.
        // Padrão: relatório (só avisa no console). Para impor, defina
        // CSP_MODO=impor antes de `pnpm build` e rode scripts/e2e/csp.mjs.
        headers: cabecalhosDeSeguranca(),
      },
    ];
  },
};

export default nextConfig;
