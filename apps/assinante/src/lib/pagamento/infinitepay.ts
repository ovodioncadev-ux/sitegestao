import type { AvisoLido, MetodoPagamento, PagamentoConferido, PedidoDeLink, ProvedorPagamento } from './tipos.ts';

/**
 * ╔═══════════════════════════════════════════════════════════════════════╗
 * ║  ADAPTADOR DA INFINITEPAY — CONTRATO A CONFIRMAR                      ║
 * ╚═══════════════════════════════════════════════════════════════════════╝
 *
 * Escrito SEM acesso à documentação oficial (o domínio estava bloqueado no
 * ambiente de desenvolvimento). Os nomes abaixo — `order_nsu`, `handle`,
 * `webhook_url`, `transaction_nsu`, `slug` e o endereço de `payment_check` —
 * vêm de fontes secundárias; o endereço de criação de link, os nomes dos campos
 * de item/valor e a UNIDADE dos valores (centavos?) são suposições.
 *
 * Por isso este adaptador:
 *   · só liga com INFINITEPAY_CONTRATO_CONFIRMADO=sim (e recusa se faltar o handle);
 *   · NUNCA confia no corpo do aviso: sempre consulta `payment_check`;
 *   · se a unidade do valor estiver errada, o efeito é "pagamento divergente"
 *     (nenhuma fatura é paga a menos) — falha para o lado seguro.
 *
 * Para confirmar: abrir https://www.infinitepay.io/checkout-documentacao e
 * conferir cada constante e campo marcado com «A CONFIRMAR», depois ligar a variável.
 */

const URL_CRIAR_LINK = 'https://api.checkout.infinitepay.io/links'; // A CONFIRMAR
const URL_CONSULTA = 'https://api.checkout.infinitepay.io/payment_check'; // A CONFIRMAR (citado em fonte secundária)
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function criarInfinitePay(opcoes: { handle: string; contratoConfirmado: boolean }): ProvedorPagamento {
  if (!opcoes.contratoConfirmado) {
    throw new Error(
      'InfinitePay: contrato da API ainda não confirmado contra a documentação oficial. ' +
        'Confira apps/assinante/src/lib/pagamento/infinitepay.ts e defina INFINITEPAY_CONTRATO_CONFIRMADO=sim.',
    );
  }
  if (!opcoes.handle) throw new Error('InfinitePay: defina INFINITEPAY_HANDLE (a InfiniteTag, sem o "$").');
  const { handle } = opcoes;

  return {
    nome: 'infinitepay',

    async criarLink(pedido: PedidoDeLink) {
      const res = await fetch(URL_CRIAR_LINK, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          handle,
          order_nsu: pedido.faturaId,
          items: [{ quantity: 1, price: pedido.valorCentavos, description: pedido.descricao }], // A CONFIRMAR: campos e unidade
          redirect_url: pedido.urlRetorno,
          webhook_url: pedido.urlAviso,
        }),
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) throw new Error(`InfinitePay recusou a criação do link (HTTP ${res.status}).`);
      const corpo = (await res.json()) as { url?: string; link?: string; checkout_url?: string }; // A CONFIRMAR: nome do campo
      const url = corpo.url ?? corpo.link ?? corpo.checkout_url;
      if (typeof url !== 'string' || !url.startsWith('https://')) {
        throw new Error('InfinitePay não devolveu um link https.');
      }
      return { url };
    },

    lerAviso(corpo: unknown): AvisoLido | null {
      if (typeof corpo !== 'object' || corpo === null) return null;
      const c = corpo as Record<string, unknown>;
      // order_nsu é o id da fatura que NÓS enviamos ao criar o link.
      if (typeof c.order_nsu !== 'string' || !UUID.test(c.order_nsu)) return null;
      const dados: Record<string, string> = {};
      // Só repassamos o que a consulta pede; os valores do corpo não são usados como prova.
      for (const chave of ['transaction_nsu', 'invoice_slug']) {
        if (typeof c[chave] === 'string' && (c[chave] as string).length <= 200) dados[chave] = c[chave] as string;
      }
      if (!dados.transaction_nsu) return null;
      return { faturaId: c.order_nsu, dadosDeConsulta: dados };
    },

    async conferir(aviso: AvisoLido): Promise<PagamentoConferido | null> {
      const transacao = aviso.dadosDeConsulta.transaction_nsu;
      if (!transacao) return null;
      const res = await fetch(URL_CONSULTA, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          handle,
          order_nsu: aviso.faturaId,
          transaction_nsu: transacao,
          slug: aviso.dadosDeConsulta.invoice_slug, // A CONFIRMAR: o nome é "slug" na consulta
        }),
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) throw new Error(`InfinitePay: consulta de pagamento falhou (HTTP ${res.status}).`);
      const corpo = (await res.json()) as {
        success?: boolean;
        paid?: boolean;
        paid_amount?: number;
        capture_method?: string;
      }; // A CONFIRMAR: nomes e unidade de paid_amount

      if (!corpo.success || !corpo.paid) return null;
      const valor = corpo.paid_amount;
      if (typeof valor !== 'number' || !Number.isInteger(valor) || valor < 0) {
        throw new Error('InfinitePay devolveu um valor pago que não é inteiro em centavos.');
      }
      return {
        pago: true,
        transacaoId: transacao,
        valorPagoCentavos: valor,
        metodo: metodoDe(corpo.capture_method),
      };
    },
  };
}

function metodoDe(captura: string | undefined): MetodoPagamento {
  const c = (captura ?? '').toLowerCase();
  if (c.includes('pix')) return 'pix';
  if (c.includes('credit') || c.includes('debit') || c.includes('card') || c.includes('cartao')) return 'cartao';
  return 'outro';
}
