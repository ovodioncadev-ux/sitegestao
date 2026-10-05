/**
 * Armazenamento do limite de tentativas do Better Auth no Postgres, para que o
 * contador valha entre todas as instâncias (a versão padrão é memória do processo).
 *
 * Implementa o contrato `BetterAuthRateLimitStorage.consume` da biblioteca:
 * registra UMA requisição na janela e diz se passa — numa única ida ao banco
 * (consumir_rate_limit, upsert atômico).
 *
 * Se o banco falhar, LIBERA e registra: o limite é um freio contra abuso, e uma
 * falha do contador não pode trancar o login de todo mundo. (A falha do banco já
 * derrubaria o login de qualquer jeito, mas por outro caminho e com outra mensagem.)
 *
 * Sem dependência de `server-only` nem do Better Auth: recebe a função de consulta,
 * para poder ser testado sem banco.
 */

export type Consulta = (
  sql: string,
  parametros: unknown[],
) => Promise<{ rows: { permitido: boolean; retry_apos: number }[] }>;

export type RegraDeLimite = { window: number; max: number };

export function criarArmazenamentoDeLimite(
  consultar: Consulta,
  registrarErro: (mensagem: string) => void = (m) => console.error(m),
) {
  return {
    async consume(key: string, rule: RegraDeLimite): Promise<{ allowed: boolean; retryAfter: number | null }> {
      try {
        const { rows } = await consultar('select permitido, retry_apos from consumir_rate_limit($1, $2, $3)', [
          key,
          rule.max,
          rule.window,
        ]);
        const linha = rows[0];
        if (!linha) return { allowed: true, retryAfter: null };
        return { allowed: linha.permitido, retryAfter: linha.permitido ? null : linha.retry_apos };
      } catch (erro) {
        registrarErro(`[rate limit auth] contador indisponível, liberando: ${erro instanceof Error ? erro.message : erro}`);
        return { allowed: true, retryAfter: null };
      }
    },
  };
}
