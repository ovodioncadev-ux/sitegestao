import { createAuthClient } from 'better-auth/client';

/**
 * Cliente de navegador do Better Auth. Sem 'server-only' de propósito —
 * é o único arquivo deste pacote que pode ser importado por um Client
 * Component. Nunca importe './better-auth' (o servidor) do navegador: lá
 * mora a conexão administrativa.
 *
 * Sem baseURL: por padrão ele fala com /api/auth no mesmo domínio de quem
 * o importa, o que é exatamente o que os dois apps (gestao e assinante)
 * precisam, cada um com sua própria rota.
 */
export const authClient = createAuthClient();
