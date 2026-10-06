/** Texto que a pessoa vê para cada valor de enum do banco. */

export const STATUS_CLIENTE = {
  pre_venda: 'Pré-venda (fora da área)',
  cadastro_andamento: 'Cadastro em andamento',
  ativo: 'Ativo',
  suspenso: 'Suspenso',
  cancelado: 'Cancelado',
} as const;

export const STATUS_ASSINATURA = {
  ativa: 'Ativa',
  pausada: 'Pausada',
  cancelada: 'Cancelada',
  encerrada: 'Encerrada',
} as const;

export const STATUS_ENTREGA = {
  pendente: 'Pendente',
  entregue: 'Entregue',
  nao_entregue: 'Não entregue',
  cancelada: 'Cancelada',
} as const;

export const STATUS_FATURA = {
  pendente: 'Pendente',
  paga: 'Paga',
  atrasada: 'Atrasada',
  cancelada: 'Cancelada',
} as const;

export const METODO_PAGAMENTO = {
  pix: 'PIX',
  dinheiro: 'Dinheiro',
  transferencia: 'Transferência',
  cartao: 'Cartão',
  outro: 'Outro',
} as const;

export const FORMA_COBRANCA = {
  pix: 'PIX (cobrança mensal manual)',
  cartao: 'Cartão (recorrência)',
} as const;

export const STATUS_REPOSICAO = {
  pendente: 'A repor',
  reposta: 'Reposta',
  cancelada: 'Cancelada',
} as const;

export const STATUS_SOLICITACAO = {
  pendente: 'Aguardando resposta',
  atendida: 'Atendida',
  recusada: 'Recusada',
} as const;

export const TIPO_SOLICITACAO = {
  pausa: 'Pausar',
  cancelamento: 'Cancelar',
  troca_plano: 'Trocar de plano',
  duzia: 'Dúzias por entrega',
} as const;

export const CHAVES_STATUS_CLIENTE = Object.keys(STATUS_CLIENTE) as (keyof typeof STATUS_CLIENTE)[];
export const CHAVES_FORMA_COBRANCA = Object.keys(FORMA_COBRANCA) as (keyof typeof FORMA_COBRANCA)[];
export const CHAVES_METODO = Object.keys(METODO_PAGAMENTO) as (keyof typeof METODO_PAGAMENTO)[];

export function rotulo<T extends Record<string, string>>(tabela: T, chave: string): string {
  return tabela[chave] ?? chave;
}
