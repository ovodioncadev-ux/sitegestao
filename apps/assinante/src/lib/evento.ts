import type { Executor } from '@ovo/database';

/**
 * Etapas do funil de assinatura. A mesma lista vive no banco (registrar_evento_funil):
 * lá é a que vale; aqui serve para recusar cedo e tipar quem chama.
 */
export const ETAPAS_FUNIL = ['plano_clicado', 'conta_criada', 'endereco_salvo', 'assinatura_confirmada'] as const;
export type EtapaFunil = (typeof ETAPAS_FUNIL)[number];

export function ehEtapaFunil(valor: unknown): valor is EtapaFunil {
  return typeof valor === 'string' && (ETAPAS_FUNIL as readonly string[]).includes(valor);
}

/**
 * Conta a etapa. Só etapa e plano público: nada de e-mail, id ou IP.
 * Dentro de uma transação já aberta: quem chama decide se uma falha da
 * contagem pode derrubar a operação (nas actions, derruba junto, de propósito:
 * a contagem e o fato andam na mesma transação).
 */
export async function registrarEvento(bd: Executor, etapa: EtapaFunil, plano: string | null = null) {
  await bd.consultar('select registrar_evento_funil($1, $2)', [etapa, plano]);
}
