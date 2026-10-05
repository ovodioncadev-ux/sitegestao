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
        // CSP em report-only por enquanto: ela avisa no console o que
        // bloquearia, sem quebrar a página. Quando o relatório vier limpo
        // por alguns dias, passe { modoRelatorio: false }.
        headers: cabecalhosDeSeguranca(),
      },
    ];
  },
};

export default nextConfig;
