import { CONSENTIMENTO_VERSAO } from '@ovo/config/privacidade';
import { comoAnonimo } from '@ovo/database';
import { lerJsonLimitado } from '@/lib/corpo';
import { lerInteresse } from '@/lib/interesse';
import { acessoBloqueado } from '@/lib/limite-publico';

export const dynamic = 'force-dynamic';

/**
 * "Avise-me quando chegar ao meu CEP": quem está fora da área deixa telefone ou
 * e-mail. Dado pessoal, então:
 *   - consentimento explícito; a VERSÃO do texto vem do servidor, não do navegador;
 *   - campo-isca (honeypot) e limite de 5 pedidos por minuto por IP;
 *   - resposta igual para pedido novo, repetido e CEP já atendido (204): a rota
 *     não confirma se um contato já estava na lista.
 */
export async function POST(request: Request) {
  // Um pedido legítimo cabe em poucas centenas de bytes: teto de 4 KB.
  const corpo = await lerJsonLimitado(request, 4096);
  if (!corpo.ok) {
    return Response.json({ erro: corpo.status === 413 ? 'Pedido grande demais.' : 'Pedido inválido.' }, { status: corpo.status });
  }

  const leitura = lerInteresse(corpo.valor);
  if (leitura.ok === 'isca') return new Response(null, { status: 204 });
  if (leitura.ok === false) return Response.json({ erro: leitura.erro }, { status: 400 });

  const { nome, telefone, email, cep, origem } = leitura.dados;
  try {
    const bloqueado = await comoAnonimo(async (bd) => {
      if (await acessoBloqueado(bd, request.headers, 'interesse')) return true;
      await bd.consultar('select registrar_interesse($1, $2, $3, $4, $5, $6)', [
        nome,
        telefone,
        email,
        cep,
        origem,
        CONSENTIMENTO_VERSAO,
      ]);
      return false;
    });
    if (bloqueado) {
      return Response.json(
        { erro: 'Muitos pedidos seguidos. Tente de novo em um minuto.' },
        { status: 429, headers: { 'Retry-After': '60' } },
      );
    }
    return new Response(null, { status: 204 });
  } catch (erro) {
    // Sem dado pessoal no log: só o erro do banco.
    console.error('[/api/interesse]', erro instanceof Error ? erro.message : erro);
    return Response.json({ erro: 'Não foi possível registrar agora. Tente de novo em instantes.' }, { status: 500 });
  }
}
