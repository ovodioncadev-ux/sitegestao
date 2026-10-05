/**
 * Cache curto, em memória, para as respostas PÚBLICAS da vitrine (planos e
 * bairros). Cada visita ao site dispara essas leituras, e cada uma custa ~0,5 s
 * de ida e volta ao banco — além de ocupar uma conexão do pool. O dado muda só
 * quando o dono edita planos/faixas de CEP, então 30 s de atraso não faz
 * diferença.
 *
 * Nunca use para nada que dependa de quem está logado: a chave é só o nome do
 * recurso. Guarda a Promise, então visitas simultâneas dividem uma única leitura.
 * Erro não fica guardado.
 */
const guardados = new Map<string, { expira: number; valor: Promise<unknown> }>();

export const TTL_VITRINE_MS = 30_000;

export function comCachePublico<T>(chave: string, ttlMs: number, carregar: () => Promise<T>): Promise<T> {
  const agora = Date.now();
  const existente = guardados.get(chave);
  if (existente && existente.expira > agora) return existente.valor as Promise<T>;

  const valor = carregar();
  guardados.set(chave, { expira: agora + ttlMs, valor });
  valor.catch(() => {
    if (guardados.get(chave)?.valor === valor) guardados.delete(chave);
  });
  return valor;
}

/** Cabeçalho para respostas públicas: quem estiver na frente (CDN) também pode guardar por pouco tempo. */
export const CABECALHO_VITRINE = { 'Cache-Control': 'public, s-maxage=30, stale-while-revalidate=60' } as const;
