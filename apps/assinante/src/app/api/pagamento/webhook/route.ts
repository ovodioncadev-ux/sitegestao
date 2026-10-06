import { comoAnonimo, comoPagamentos } from '@ovo/database';
import { lerJsonLimitado } from '@/lib/corpo';
import { acessoBloqueado } from '@/lib/limite-publico';
import { processarAviso, type ConfirmacaoNoBanco } from '@/lib/pagamento/aviso';
import { obterProvedor } from '@/lib/pagamento/provedor';

export const dynamic = 'force-dynamic';

/** Um aviso real tem poucas centenas de bytes. Acima disso nem lemos. */
const TAMANHO_MAXIMO = 20_000;

/**
 * ÚNICO lugar que usa `comoPagamentos` (scripts/verificar-segredos.sh confere).
 *
 * Aviso de pagamento do provedor. Qualquer pessoa pode mandar um POST para cá,
 * então o corpo NUNCA prova nada: processarAviso() pergunta ao provedor se foi
 * pago e quanto, e só com a resposta DELE o banco é chamado — pelo papel
 * app_pagamentos, que só consegue executar a confirmação. O banco ainda confere
 * o valor contra o da fatura e ignora transação repetida.
 *
 * Respostas: 200 = recebido (inclusive "não pago" e "já processado"); 400 =
 * corpo que não é aviso; 429 = muitos avisos do mesmo IP; 502 = não deu para
 * consultar o provedor agora (ele reenvia). 404 = pagamento online desligado.
 */
export async function POST(request: Request) {
  let provedor;
  try {
    provedor = obterProvedor();
  } catch (erro) {
    console.error('[webhook pagamento] configuração inválida:', erro instanceof Error ? erro.message : erro);
    return new Response(null, { status: 503 });
  }
  if (!provedor) return new Response(null, { status: 404 });

  const bloqueado = await comoAnonimo((bd) => acessoBloqueado(bd, request.headers, 'webhook')).catch(() => false);
  if (bloqueado) return new Response(null, { status: 429, headers: { 'Retry-After': '60' } });

  // Lido em fluxo, com teto, inclusive sem Content-Length (ver lib/corpo.ts).
  const leitura = await lerJsonLimitado(request, TAMANHO_MAXIMO);
  if (!leitura.ok) return new Response(null, { status: leitura.status });
  const corpo = leitura.valor;

  const confirmar: ConfirmacaoNoBanco = async (d) => {
    try {
      const linha = await comoPagamentos((bd) =>
        bd.umaLinha<{ resultado: string }>('select confirmar_pagamento_online($1, $2, $3, $4, $5) as resultado', [
          d.faturaId,
          d.provedor,
          d.transacaoId,
          d.valorPagoCentavos,
          d.metodo,
        ]),
      );
      return (linha?.resultado ?? 'sem_efeito') as Awaited<ReturnType<ConfirmacaoNoBanco>>;
    } catch (erro) {
      // OV001 = o banco recusou o aviso (fatura que não existe, dado inválido).
      // Reenviar não adianta: responde "recebido" e registra, sem dado pessoal.
      if ((erro as { code?: string })?.code === 'OV001') {
        console.error('[webhook pagamento] recusado pelo banco:', (erro as Error).message);
        return 'fatura_desconhecida';
      }
      throw erro;
    }
  };

  try {
    const resultado = await processarAviso(provedor, corpo, confirmar);
    switch (resultado.tipo) {
      case 'invalido':
        return new Response(null, { status: 400 });
      case 'indisponivel':
        return new Response(null, { status: 502 });
      case 'nao_pago':
        return Response.json({ ok: true, resultado: 'nao_pago' });
      case 'processado':
        return Response.json({ ok: true, resultado: resultado.resultado });
    }
  } catch (erro) {
    console.error('[webhook pagamento] erro inesperado:', erro instanceof Error ? erro.message : erro);
    return new Response(null, { status: 500 });
  }
}
