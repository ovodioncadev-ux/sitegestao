import { comoAnonimo } from '@ovo/database';
import { acessoBloqueado } from '@/lib/limite-publico';

export const dynamic = 'force-dynamic';

/**
 * "Meu CEP é atendido?" — resposta só sim/não, calculada pelo banco a partir
 * das faixas ativas. É informação pública (a vitrine já lista os bairros);
 * não devolve endereço nem dado de ninguém.
 *
 * Sem cache (cada CEP é uma consulta), então tem limite por IP no banco.
 */
export async function GET(request: Request) {
  const cep = (new URL(request.url).searchParams.get('cep') ?? '').replace(/\D/g, '');
  if (cep.length !== 8) {
    return Response.json({ erro: 'CEP precisa ter 8 dígitos.' }, { status: 400 });
  }

  try {
    const resposta = await comoAnonimo(async (bd) => {
      if (await acessoBloqueado(bd, request.headers, 'area')) return { bloqueado: true as const };
      const linha = await bd.umaLinha<{ atendido: boolean }>('select cep_dentro_area_entrega($1) as atendido', [cep]);
      return { bloqueado: false as const, atendido: Boolean(linha?.atendido) };
    });
    if (resposta.bloqueado) {
      return Response.json(
        { erro: 'Muitas consultas seguidas. Tente de novo em um minuto.' },
        { status: 429, headers: { 'Retry-After': '60' } },
      );
    }
    return Response.json({ atendido: resposta.atendido });
  } catch (erro) {
    console.error('[/api/area]', erro);
    return Response.json({ erro: 'Não foi possível consultar a área agora.' }, { status: 500 });
  }
}
