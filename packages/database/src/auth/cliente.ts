import { createAuthClient } from 'better-auth/client';

/**
 * Cliente de navegador do Better Auth. Sem 'server-only' de propósito —
 * é o único arquivo deste pacote que pode ser importado por um Client
 * Component. Nunca importe './better-auth' (o servidor) do navegador: lá
 * mora a conexão administrativa.
 *
 * Sem baseURL: ele fala com o mesmo domínio de quem o importa. O caminho vem
 * de NEXT_PUBLIC_BASE_PATH (/conta ou /gestao), definido no next.config.ts de
 * cada app, então cada um chama a sua própria rota /api/auth.
 */
export const authClient = createAuthClient({
  basePath: `${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}/api/auth`,
});
