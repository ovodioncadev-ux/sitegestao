import { comoAnonimo } from '@ovo/database';
import { CABECALHO_VITRINE, TTL_VITRINE_MS, comCachePublico } from '@/lib/cache-publico';

export const dynamic = 'force-dynamic';

/**
 * Bairros atendidos = bairros das faixas de CEP ativas cadastradas pelo dono
 * (Área de entrega, no painel). Não existe lista escrita no código: sem
 * faixas cadastradas, a lista é vazia — e a tela diz isso, em vez de
 * prometer entrega que ninguém configurou.
 */
export async function GET() {
  try {
    const bairros = await comCachePublico('bairros', TTL_VITRINE_MS, () =>
      comoAnonimo((bd) =>
        bd.consultar<{ bairro: string }>(
          `select distinct bairro from faixas_cep_atendidas
            where ativo and bairro is not null and btrim(bairro) <> ''
            order by bairro`,
        ),
      ),
    );
    return Response.json(
      { bairros: bairros.map((b) => ({ name: b.bairro, isServed: true })) },
      { headers: CABECALHO_VITRINE },
    );
  } catch (erro) {
    console.error('[/api/neighborhoods]', erro);
    return Response.json({ erro: 'Erro ao carregar bairros' }, { status: 500 });
  }
}
