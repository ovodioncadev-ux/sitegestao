import { createHmac, timingSafeEqual } from 'node:crypto';
import type { AvisoLido, PagamentoConferido, PedidoDeLink, ProvedorPagamento } from './tipos.ts';

/**
 * Provedor de mentira, SÓ para desenvolvimento e testes. Faz o papel de um
 * provedor real: o "link" leva a uma página nossa de simulação, e o "aviso"
 * traz uma assinatura (HMAC) que só o simulador sabe fazer — assim `conferir`
 * recusa aviso forjado, como a consulta a um provedor de verdade recusaria.
 *
 * Nunca ligado em produção (ver provedor.ts).
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function assinarSimulado(segredo: string, faturaId: string, transacaoId: string, valor: number, metodo: string): string {
  return createHmac('sha256', segredo).update(`${faturaId}|${transacaoId}|${valor}|${metodo}`).digest('hex');
}

export function criarSimulado(opcoes: { segredo: string; urlPublica: string }): ProvedorPagamento {
  const { segredo, urlPublica } = opcoes;

  return {
    nome: 'simulado',

    async criarLink(pedido: PedidoDeLink) {
      const url = new URL(`/pagamento/simulado/${pedido.faturaId}`, urlPublica);
      url.searchParams.set('valor', String(pedido.valorCentavos));
      return { url: url.toString() };
    },

    lerAviso(corpo: unknown): AvisoLido | null {
      if (typeof corpo !== 'object' || corpo === null) return null;
      const c = corpo as Record<string, unknown>;
      if (typeof c.fatura !== 'string' || !UUID.test(c.fatura)) return null;
      const dados: Record<string, string> = {};
      for (const chave of ['transacao', 'valor', 'metodo', 'assinatura']) {
        if (typeof c[chave] !== 'string' && typeof c[chave] !== 'number') return null;
        dados[chave] = String(c[chave]);
      }
      return { faturaId: c.fatura, dadosDeConsulta: dados };
    },

    async conferir(aviso: AvisoLido): Promise<PagamentoConferido | null> {
      const transacao = aviso.dadosDeConsulta.transacao ?? '';
      const valor = aviso.dadosDeConsulta.valor ?? '';
      const metodo = aviso.dadosDeConsulta.metodo ?? '';
      const assinatura = aviso.dadosDeConsulta.assinatura ?? '';
      if (!transacao || !assinatura) return null;
      const esperada = assinarSimulado(segredo, aviso.faturaId, transacao, Number(valor), metodo);
      const a = Buffer.from(assinatura);
      const b = Buffer.from(esperada);
      // Assinatura errada = o "provedor" não reconhece este pagamento.
      if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
      return {
        pago: true,
        transacaoId: transacao,
        valorPagoCentavos: Number(valor),
        metodo: metodo === 'pix' || metodo === 'cartao' ? metodo : 'outro',
      };
    },
  };
}
