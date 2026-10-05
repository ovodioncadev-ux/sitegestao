import { unstable_rethrow } from 'next/navigation';
import type { Estado } from './tipos';

/**
 * Erro cuja mensagem PODE ser mostrada à pessoa: é texto nosso, escrito para
 * ela. Qualquer outro erro é tratado como inesperado e não vaza detalhe.
 */
export class ErroNegocio extends Error {}

/**
 * Regra de negócio quebrada dentro do banco. As funções SQL usam este código
 * (`raise exception ... using errcode = 'OV001'`) para dizer "esta mensagem é
 * para a pessoa". Qualquer outro erro do Postgres é interno e não é exibido.
 */
const CODIGO_NEGOCIO = 'OV001';

/** Violação de unicidade → frase legível, pelo nome da constraint/índice. */
const DUPLICIDADES: Record<string, string> = {
  clientes_email_unico_idx: 'E-mail já cadastrado.',
  clientes_usuario_id_key: 'Esta conta de login já está vinculada a outro cliente.',
  clientes_codigo_indicacao_key: 'Esse código de indicação já está em uso.',
  assinaturas_vigente_idx: 'Este cliente já tem uma assinatura ativa ou pausada.',
  entregas_data_unica_idx: 'Já existe uma entrega dessa assinatura nessa data.',
  faturas_vencimento_unico_idx: 'Já existe uma fatura dessa assinatura com esse vencimento.',
  faturas_periodo_unico_idx: 'Já existe uma fatura para esse período da assinatura.',
  solicitacoes_pendente_idx: 'Já existe uma solicitação pendente desse tipo para esta assinatura.',
};

type ErroDePostgres = { code?: string; constraint?: string; message?: string };

export function traduzirErro(erro: unknown): string {
  if (erro instanceof ErroNegocio) return erro.message;

  const pg = erro as ErroDePostgres;
  if (pg?.code === CODIGO_NEGOCIO && pg.message) return pg.message;
  if (pg?.code === '23505') {
    return (pg.constraint && DUPLICIDADES[pg.constraint]) || 'Já existe um registro igual a este.';
  }
  if (pg?.code === '23503' || pg?.code === '23001') return 'Este registro está ligado a outros e não pode ser alterado assim.';
  if (pg?.code === '23514') return 'Algum valor informado não é aceito. Confira os campos.';
  if (pg?.code === '22P02') return 'Identificador inválido.';
  if (pg?.code === '22007' || pg?.code === '22008') return 'Data inválida.';

  // Erro que não previmos: registra no servidor, não mostra o texto à pessoa.
  console.error('[erro inesperado em ação]', erro);
  return 'Erro inesperado. Nada foi salvo — tente de novo.';
}

/**
 * Envolve o trabalho de uma Server Action: o que ele devolver é a mensagem de
 * sucesso; qualquer falha vira mensagem de erro clara, nunca a tela de erro
 * genérica do Next.
 */
export async function rodar(trabalho: () => Promise<string>): Promise<Estado> {
  try {
    return { ok: true, mensagem: await trabalho() };
  } catch (erro) {
    // redirect() e notFound() do Next são lançados como erro; não podem ser engolidos.
    unstable_rethrow(erro);
    return { ok: false, mensagem: traduzirErro(erro) };
  }
}
