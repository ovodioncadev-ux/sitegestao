/**
 * Contrato entre o sistema e um provedor de pagamento online.
 *
 * REGRA DE OURO: o corpo de um aviso (webhook) NÃO prova pagamento — qualquer
 * pessoa pode mandar um POST para a nossa URL. `lerAviso` só descobre DE QUAL
 * fatura o aviso fala; quem diz se foi pago, quanto e por qual meio é a
 * consulta feita por nós ao provedor (`conferir`). Só o resultado dela chega
 * ao banco.
 */

export type MetodoPagamento = 'pix' | 'cartao' | 'outro';

export type PedidoDeLink = {
  /** Id da fatura: é também a referência (order_nsu) que volta no aviso. */
  faturaId: string;
  valorCentavos: number;
  descricao: string;
  /** Para onde o provedor devolve a pessoa depois de pagar. */
  urlRetorno: string;
  /** Endereço público que o provedor chama quando o pagamento acontecer. */
  urlAviso: string;
};

/** O que se consegue tirar do corpo do aviso. NÃO é confiável. */
export type AvisoLido = {
  faturaId: string;
  /** Dados que o provedor pede de volta na consulta (ex.: id da transação, slug). */
  dadosDeConsulta: Record<string, string>;
};

/** O que o PROVEDOR confirmou, ao ser consultado por nós. */
export type PagamentoConferido = {
  pago: boolean;
  transacaoId: string;
  valorPagoCentavos: number;
  metodo: MetodoPagamento;
};

export interface ProvedorPagamento {
  /** Identificador estável gravado em pagamentos_online.provedor. */
  readonly nome: string;
  criarLink(pedido: PedidoDeLink): Promise<{ url: string }>;
  lerAviso(corpo: unknown): AvisoLido | null;
  conferir(aviso: AvisoLido): Promise<PagamentoConferido | null>;
}
