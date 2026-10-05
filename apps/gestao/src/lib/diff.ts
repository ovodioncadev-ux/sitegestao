/**
 * Transforma o "antes" e o "depois" de uma linha de auditoria em uma lista de
 * mudanças legíveis. Só os campos que mudaram aparecem — o resto é ruído.
 */

export type Mudanca = { campo: string; antes: string; depois: string };

const IGNORAR = new Set(['atualizado_em', 'criado_em']);

/** Nomes de campo em português, para os que a pessoa mais consulta. */
const NOMES: Record<string, string> = {
  nome: 'Nome',
  email: 'E-mail',
  telefone: 'Telefone',
  cep: 'CEP',
  endereco: 'Endereço',
  numero: 'Número',
  complemento: 'Complemento',
  bairro: 'Bairro',
  cidade: 'Cidade',
  estado: 'Estado',
  status: 'Situação',
  plano_id: 'Plano (id)',
  usuario_id: 'Conta de login',
  dentro_area_entrega: 'Dentro da área',
  data_prevista: 'Data prevista',
  data_realizada: 'Realizada em',
  data_pagamento: 'Data do pagamento',
  data_cancelamento: 'Cancelada em',
  motivo_cancelamento: 'Motivo do cancelamento',
  valor_centavos: 'Valor (centavos)',
  vencimento: 'Vencimento',
  metodo: 'Método',
  observacao: 'Observação',
  proxima_entrega: 'Próxima entrega',
  pentes: 'Pentes',
  duzias: 'Dúzias',
  forma_cobranca: 'Forma de cobrança',
  proxima_cobranca: 'Próxima cobrança',
  pausada_em: 'Pausada em',
  data_retorno_prevista: 'Retorno previsto',
  periodo_inicio: 'Período (início)',
  periodo_fim: 'Período (fim)',
  horario_previsto: 'Horário previsto',
  quantidade_ovos: 'Ovos com defeito',
  descricao: 'Descrição',
  entrega_reposicao_id: 'Entrega da reposição',
  reposta_em: 'Reposta em',
  resposta: 'Resposta',
  resolvida_em: 'Resolvida em',
};

function texto(valor: unknown): string {
  if (valor === null || valor === undefined) return '—';
  if (typeof valor === 'boolean') return valor ? 'sim' : 'não';
  if (typeof valor === 'object') return JSON.stringify(valor);
  return String(valor);
}

export function calcularMudancas(
  antes: Record<string, unknown> | null,
  depois: Record<string, unknown> | null,
): Mudanca[] {
  const chaves = new Set([...Object.keys(antes ?? {}), ...Object.keys(depois ?? {})]);
  const mudancas: Mudanca[] = [];

  for (const chave of chaves) {
    if (IGNORAR.has(chave)) continue;
    const a = antes?.[chave];
    const d = depois?.[chave];
    // Registro novo: mostra o que foi preenchido, não uma lista de "— → —".
    if (antes === null && (d === null || d === undefined)) continue;
    if (antes !== null && depois !== null && JSON.stringify(a) === JSON.stringify(d)) continue;
    mudancas.push({ campo: NOMES[chave] ?? chave, antes: texto(a), depois: texto(d) });
  }
  return mudancas;
}
