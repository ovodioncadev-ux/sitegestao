import { comoAnonimo } from '@ovo/database';
import { CABECALHO_VITRINE, TTL_VITRINE_MS, comCachePublico } from '@/lib/cache-publico';

// Conteúdo público do site: textos e regras de exibição, sem dado de cliente.
export const dynamic = 'force-dynamic';

type LinhaConteudo = {
  freshness_max_dias: number | null;
  frete_gratis: boolean;
  desconto_primeiro_mes_pct: string | null;
  dia_corte: number | null;
  hora_corte: string | null;
};

export async function GET() {
  try {
    const dados = await comCachePublico('site', TTL_VITRINE_MS, () =>
      comoAnonimo(async (bd) => {
        const conteudo = await bd.umaLinha<LinhaConteudo>('select * from site_conteudo()');
        const faq = await bd.consultar<{ pergunta: string; resposta: string }>(
          'select pergunta, resposta from faq_itens where ativo order by ordem, id',
        );
        return { conteudo, faq };
      }),
    );

    const c = dados.conteudo;
    return Response.json(
      {
        // Nulo = não há plano ativo: o site não afirma nada.
        freshnessMaxDays: c?.freshness_max_dias ?? null,
        freeShipping: Boolean(c?.frete_gratis),
        firstMonthDiscountPct: c?.desconto_primeiro_mes_pct == null ? null : Number(c.desconto_primeiro_mes_pct),
        cutoff: c?.dia_corte == null || !c.hora_corte ? null : { weekday: c.dia_corte, time: c.hora_corte },
        faq: dados.faq.map((f) => ({ question: f.pergunta, answer: f.resposta })),
      },
      { headers: CABECALHO_VITRINE },
    );
  } catch (erro) {
    console.error('[/api/site]', erro);
    return Response.json({ erro: 'Erro ao carregar o conteúdo do site' }, { status: 500 });
  }
}
