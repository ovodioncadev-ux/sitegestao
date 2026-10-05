import { comoAnonimo } from '@ovo/database';
import { CABECALHO_VITRINE, TTL_VITRINE_MS, comCachePublico } from '@/lib/cache-publico';
import { lerPlanosPublicos } from '@/lib/planos';

// Vitrine pública: dado de configuração, sem informação de cliente.
export const dynamic = 'force-dynamic';

export async function GET() {
  try {
    const planos = await comCachePublico('planos', TTL_VITRINE_MS, () => comoAnonimo((bd) => lerPlanosPublicos(bd)));

    return Response.json(
      {
        planos: planos.map((p) => ({
          frequencia: p.frequencia,
          nome: p.nome,
          intervalDays: p.intervaloDias,
          priceCents: p.precoCentavos,
          freshnessMaxDays: p.freshnessMaxDias,
          freightCents: p.freteCentavos,
          firstMonthDiscountPct: p.descontoPrimeiroMesPct,
          badge: p.selo,
          // Só o que o banco sabe afirmar: nada de "frete grátis" ou "quarta-feira" fixos no código.
          features: [
            'Ovos caipiras, direto da fazenda',
            ...(p.ancorarEmQuarta ? ['Entrega em dia fixo (quarta-feira)'] : []),
          ],
        })),
      },
      { headers: CABECALHO_VITRINE },
    );
  } catch (erro) {
    console.error('[/api/plans]', erro);
    return Response.json({ erro: 'Erro ao carregar planos' }, { status: 500 });
  }
}
