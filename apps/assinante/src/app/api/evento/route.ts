import { comoAnonimo } from '@ovo/database';
import { ehEtapaFunil, registrarEvento } from '@/lib/evento';
import { acessoBloqueado } from '@/lib/limite-publico';
import { ehFrequencia } from '@/lib/planos';

export const dynamic = 'force-dynamic';

/**
 * Contagem anônima do funil, chamada pelo navegador (site: plano clicado;
 * cadastro: conta criada). Corpo: { etapa, plano? }. Não grava IP nem identifica
 * ninguém; o IP só alimenta o limite por minuto. Quem quiser inflar o número
 * esbarra no limite, e o dado é só de contagem — não decide nada no sistema.
 */
export async function POST(request: Request) {
  let corpo: unknown;
  try {
    corpo = await request.json();
  } catch {
    return new Response(null, { status: 400 });
  }

  const { etapa, plano } = (corpo ?? {}) as { etapa?: unknown; plano?: unknown };
  if (!ehEtapaFunil(etapa)) return new Response(null, { status: 400 });
  if (plano !== undefined && plano !== null && !ehFrequencia(plano)) return new Response(null, { status: 400 });

  try {
    const bloqueado = await comoAnonimo(async (bd) => {
      if (await acessoBloqueado(bd, request.headers, 'evento')) return true;
      await registrarEvento(bd, etapa, (plano as string | null | undefined) ?? null);
      return false;
    });
    return new Response(null, { status: bloqueado ? 429 : 204 });
  } catch (erro) {
    console.error('[/api/evento]', erro);
    // A contagem não pode incomodar quem está assinando: falha em silêncio para o navegador.
    return new Response(null, { status: 204 });
  }
}
