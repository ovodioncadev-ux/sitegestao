import { comoAnonimo } from '@ovo/database';

export const dynamic = 'force-dynamic';

/**
 * "Meu CEP é atendido?" — resposta só sim/não, calculada pelo banco a partir
 * das faixas ativas. É informação pública (a vitrine já lista os bairros);
 * não devolve endereço nem dado de ninguém.
 */
export async function GET(request: Request) {
  const cep = (new URL(request.url).searchParams.get('cep') ?? '').replace(/\D/g, '');
  if (cep.length !== 8) {
    return Response.json({ erro: 'CEP precisa ter 8 dígitos.' }, { status: 400 });
  }

  try {
    const linha = await comoAnonimo((bd) =>
      bd.umaLinha<{ atendido: boolean }>('select cep_dentro_area_entrega($1) as atendido', [cep]),
    );
    return Response.json({ atendido: Boolean(linha?.atendido) });
  } catch (erro) {
    console.error('[/api/area]', erro);
    return Response.json({ erro: 'Não foi possível consultar a área agora.' }, { status: 500 });
  }
}
