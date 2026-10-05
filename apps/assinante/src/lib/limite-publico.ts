import type { Executor } from '@ovo/database';

/**
 * IP de quem chamou, para o contador de rotas públicas. Só vale atrás de um
 * proxy que reescreva `x-forwarded-for` (Vercel, Cloudflare): sem ele o
 * cabeçalho é do cliente e o limite é só um freio, não uma garantia.
 */
export function ipDaRequisicao(cabecalhos: Pick<Headers, 'get'>): string {
  const encaminhado = cabecalhos.get('x-forwarded-for')?.split(',')[0]?.trim();
  return encaminhado || cabecalhos.get('x-real-ip')?.trim() || 'desconhecido';
}

/**
 * `true` = bloqueado. O banco decide (limitar_acesso_publico: rotas e limites
 * fixos lá). Se o contador falhar, a vitrine NÃO sai do ar: libera e registra.
 * O savepoint existe porque um erro SQL aborta a transação inteira; sem ele o
 * "libera" seria só de fachada e a consulta seguinte falharia junto.
 */
export async function acessoBloqueado(bd: Executor, cabecalhos: Pick<Headers, 'get'>, rota: 'area' | 'evento' | 'interesse'): Promise<boolean> {
  await bd.consultar('savepoint limite_publico');
  try {
    const linha = await bd.umaLinha<{ bloqueado: boolean }>('select limitar_acesso_publico($1, $2) as bloqueado', [
      ipDaRequisicao(cabecalhos),
      rota,
    ]);
    await bd.consultar('release savepoint limite_publico');
    return Boolean(linha?.bloqueado);
  } catch (erro) {
    console.error('[limite-publico]', erro);
    await bd.consultar('rollback to savepoint limite_publico');
    return false;
  }
}
