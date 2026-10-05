/**
 * Rate limit para Server Actions críticas
 *
 * Protege contra DDoS em operações sensíveis:
 * - assinar_plano (criação de assinatura)
 * - gerar_cobranca (geração de fatura)
 * - processar_rotina_diaria (rotina administrativa)
 *
 * Usa tabela rateLimit (Fase 10) para sincronizar entre instâncias.
 */

import { emTransacao } from './acesso';

export interface RateLimitOpcoes {
  limite: number;           // Máximo de chamadas
  periodo: string;          // 'minuto', 'hora', 'dia'
}

/**
 * Converte período textual para segundos
 */
function periodoParaSegundos(periodo: string): number {
  const mapa: Record<string, number> = {
    minuto: 60,
    hora: 3600,
    dia: 86400,
  };
  return mapa[periodo] || 3600;
}

/**
 * Wrapper que adiciona rate limit a um Server Action
 *
 * Uso:
 * ```typescript
 * export const assinar_plano = rateLimitServerAction(
 *   { limite: 10, periodo: 'hora' },
 *   async (formData) => {
 *     // lógica da action
 *   }
 * );
 * ```
 *
 * Bloqueia após atingir o limite, retornando erro 429.
 */
export function rateLimitServerAction<T>(
  opcoes: RateLimitOpcoes,
  handler: (data: T) => Promise<any>
) {
  return async (data: T) => {
    // Obter IP do cliente (Next.js headers)
    const { headers } = await import('next/headers');
    const headersList = await headers();

    // IP pode vir de X-Forwarded-For (proxy) ou remoto direto
    const ip =
      headersList.get('x-forwarded-for')?.split(',')[0] ||
      headersList.get('x-real-ip') ||
      'unknown';

    const periodo = periodoParaSegundos(opcoes.periodo);
    const nomeAction = handler.name || 'server-action';

    // Chamar função SQL que verifica rate limit
    const bloqueado = await emTransacao(async (db) => {
      const resultado = await db.query<[boolean]>(
        'SELECT verificar_rate_limit($1, $2, $3, $4)',
        [ip, nomeAction, opcoes.limite, periodo]
      );
      return resultado.rows[0]?.[0] ?? false;
    });

    if (bloqueado) {
      // Retornar erro HTTP 429 (Too Many Requests)
      throw new Error(
        `Rate limit atingido para ${nomeAction}. ` +
        `Máximo ${opcoes.limite} por ${opcoes.periodo}. ` +
        `Tente novamente em alguns ${opcoes.periodo}s.`
      );
    }

    // Rate limit OK, executar handler
    return handler(data);
  };
}

/**
 * Rate limit por usuário (em vez de IP)
 *
 * Útil para operações que requerem autenticação, onde queremos limitar
 * por usuário em vez de IP (evita bloquear múltiplos usuários no mesmo IP).
 *
 * Uso:
 * ```typescript
 * export const gerar_cobranca = rateLimitServerActionPorUsuario(
 *   { limite: 5, periodo: 'hora' },
 *   async (formData) => {
 *     const usuario = await usuarioAtual();
 *     // lógica com usuario.id
 *   }
 * );
 * ```
 */
export function rateLimitServerActionPorUsuario<T>(
  opcoes: RateLimitOpcoes,
  handler: (data: T) => Promise<any>
) {
  return async (data: T) => {
    // Importar função de autenticação
    const { usuarioAtual } = await import('./papel');

    const usuario = await usuarioAtual();
    if (!usuario) {
      throw new Error('Não autenticado');
    }

    const periodo = periodoParaSegundos(opcoes.periodo);
    const nomeAction = handler.name || 'server-action';

    // Usar ID do usuário em vez de IP
    const bloqueado = await emTransacao(async (db) => {
      const resultado = await db.query<[boolean]>(
        'SELECT verificar_rate_limit($1, $2, $3, $4)',
        [usuario.id, nomeAction, opcoes.limite, periodo]
      );
      return resultado.rows[0]?.[0] ?? false;
    });

    if (bloqueado) {
      throw new Error(
        `Rate limit atingido. ` +
        `Máximo ${opcoes.limite} por ${opcoes.periodo}. ` +
        `Tente novamente depois.`
      );
    }

    return handler(data);
  };
}
