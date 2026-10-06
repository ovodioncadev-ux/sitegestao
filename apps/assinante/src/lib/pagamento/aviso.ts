import type { MetodoPagamento, ProvedorPagamento } from './tipos.ts';

export type ConfirmacaoNoBanco = (dados: {
  faturaId: string;
  provedor: string;
  transacaoId: string;
  valorPagoCentavos: number;
  metodo: MetodoPagamento;
}) => Promise<'confirmado' | 'ja_processado' | 'divergente' | 'sem_efeito' | 'fatura_desconhecida'>;

export type ResultadoDoAviso =
  /** Corpo que não é um aviso deste provedor: 400. */
  | { tipo: 'invalido' }
  /** O provedor não respondeu à consulta: 5xx, para ele reenviar depois. */
  | { tipo: 'indisponivel' }
  /** O provedor diz que não está pago (ou não conhece a cobrança): nada a fazer. */
  | { tipo: 'nao_pago' }
  | { tipo: 'processado'; resultado: 'confirmado' | 'ja_processado' | 'divergente' | 'sem_efeito' | 'fatura_desconhecida' };

/**
 * Trata um aviso de pagamento. A ordem é o que importa para a segurança:
 *   1. lê só o suficiente do corpo para saber de qual fatura se fala;
 *   2. PERGUNTA AO PROVEDOR se foi pago e quanto (o corpo recebido é descartado);
 *   3. só então manda o banco confirmar, com os dados que o provedor devolveu.
 * O banco ainda confere o valor contra o da fatura e a idempotência.
 */
export async function processarAviso(
  provedor: ProvedorPagamento,
  corpo: unknown,
  confirmar: ConfirmacaoNoBanco,
): Promise<ResultadoDoAviso> {
  const aviso = provedor.lerAviso(corpo);
  if (!aviso) return { tipo: 'invalido' };

  let conferido;
  try {
    conferido = await provedor.conferir(aviso);
  } catch (erro) {
    console.error('[pagamento] consulta ao provedor falhou:', erro instanceof Error ? erro.message : erro);
    return { tipo: 'indisponivel' };
  }
  if (!conferido || !conferido.pago) return { tipo: 'nao_pago' };

  const resultado = await confirmar({
    faturaId: aviso.faturaId,
    provedor: provedor.nome,
    transacaoId: conferido.transacaoId,
    valorPagoCentavos: conferido.valorPagoCentavos,
    metodo: conferido.metodo,
  });
  return { tipo: 'processado', resultado };
}
