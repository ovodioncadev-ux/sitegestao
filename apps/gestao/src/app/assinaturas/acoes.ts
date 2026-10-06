'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import { CHAVES_FORMA_COBRANCA } from '@/lib/rotulos';
import type { Estado } from '@/lib/tipos';
import { formatarData } from '@/lib/formatar';
import { campo, dataOpcional, escolha, idNumerico, textoOpcional, uuid } from '@/lib/validacao';

/**
 * As regras (cliente existe, plano ativo, endereço preenchido, dentro da área,
 * uma assinatura vigente por cliente) moram nas funções SQL. Aqui só se lê o
 * formulário, se confere o formato e se chama a função — o banco é quem decide.
 * Toda escrita passa por comoDono().
 */

function atualizarTelas(clienteId?: string, assinaturaId?: string) {
  revalidatePath('/assinaturas');
  revalidatePath('/entregas');
  revalidatePath('/faturas');
  if (clienteId) revalidatePath(`/clientes/${clienteId}`);
  if (assinaturaId) revalidatePath(`/assinaturas/${assinaturaId}`);
}

export async function criarAssinatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const clienteId = uuid(campo(dados, 'cliente_id'), 'Cliente');
    const planoId = idNumerico(campo(dados, 'plano_id'), 'Plano');
    const inicio = dataOpcional(campo(dados, 'data_inicio'), 'Data de início');

    await comoDono((bd) =>
      bd.consultar('select criar_assinatura($1::uuid, $2::smallint, $3::date)', [
        clienteId,
        planoId,
        inicio,
      ]),
    );

    atualizarTelas(clienteId);
    return 'Assinatura criada.';
  });
}

export async function alterarPlanoAssinatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const planoId = idNumerico(campo(dados, 'plano_id'), 'Plano');

    await comoDono((bd) =>
      bd.consultar('select alterar_plano_assinatura($1::uuid, $2::smallint)', [assinaturaId, planoId]),
    );

    atualizarTelas(undefined, assinaturaId);
    revalidatePath('/clientes');
    return 'Plano da assinatura alterado.';
  });
}

/** Situação nova da assinatura → o que muda no cliente, nas entregas e nas faturas está no banco. */
function atualizarTudo(clienteId: string, assinaturaId: string) {
  atualizarTelas(clienteId, assinaturaId);
  revalidatePath('/clientes');
}

async function ligacoes(assinaturaId: string) {
  return comoDono((bd) =>
    bd.umaLinha<{ cliente_id: string; proxima: string | null }>(
      'select cliente_id, proxima_entrega::text as proxima from assinaturas where id = $1',
      [assinaturaId],
    ),
  );
}

export async function pausarAssinatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const motivo = textoOpcional(campo(dados, 'motivo'), 'Motivo', 500);
    const retorno = dataOpcional(campo(dados, 'retorno_previsto'), 'Retorno previsto');
    const destino = escolha(campo(dados, 'destino') || 'credito', ['credito', 'pentes'] as const, 'Compensação');

    await comoDono((bd) =>
      bd.consultar('select pausar_assinatura($1::uuid, $2::text, $3::date, $4::text)', [assinaturaId, motivo, retorno, destino]),
    );

    const l = await ligacoes(assinaturaId);
    if (l) atualizarTudo(l.cliente_id, assinaturaId);
    return retorno
      ? `Assinatura pausada até ${formatarData(retorno)}. A rotina diária reativa nessa data.`
      : 'Assinatura pausada sem data de retorno. Entregas e cobranças pendentes foram canceladas. Avise o cliente: passados 60 dias, o painel pede a sua decisão.';
  });
}

export async function cancelarAssinatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const motivo = textoOpcional(campo(dados, 'motivo'), 'Motivo', 500);

    const imediato = dados.get('imediato') === 'on';

    const agendado = await comoDono(async (bd) => {
      await bd.consultar('select cancelar_assinatura($1::uuid, $2::text, $3::boolean)', [assinaturaId, motivo, imediato]);
      return bd.umaLinha<{ agendado: string | null }>(
        'select cancelamento_agendado_para::text as agendado from assinaturas where id = $1',
        [assinaturaId],
      );
    });

    const l = await ligacoes(assinaturaId);
    if (l) atualizarTudo(l.cliente_id, assinaturaId);
    if (agendado?.agendado) {
      return `Cancelamento agendado: vale até ${formatarData(agendado.agendado)} (fim do mês pago). As entregas continuam até lá e nenhuma cobrança nova será gerada.`;
    }
    return 'Assinatura cancelada. O histórico foi mantido; entregas e faturas pendentes foram canceladas.';
  });
}

export async function desfazerCancelamentoAgendado(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    await comoDono((bd) => bd.consultar('select desfazer_cancelamento_agendado($1::uuid)', [assinaturaId]));
    const l = await ligacoes(assinaturaId);
    if (l) atualizarTudo(l.cliente_id, assinaturaId);
    return 'Cancelamento agendado desfeito. A cobrança volta a ser gerada pela rotina diária.';
  });
}

export async function reativarAssinatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const retorno = dataOpcional(campo(dados, 'retorno'), 'Data de retorno');
    const motivo = textoOpcional(campo(dados, 'motivo'), 'Motivo', 500);

    await comoDono((bd) =>
      bd.consultar('select reativar_assinatura($1::uuid, $2::date, $3::text)', [
        assinaturaId,
        retorno,
        motivo,
      ]),
    );

    const l = await ligacoes(assinaturaId);
    if (l) atualizarTudo(l.cliente_id, assinaturaId);
    return `Assinatura reativada. Próxima entrega: ${formatarData(l?.proxima)}.`;
  });
}

export async function definirFormaCobranca(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const forma = escolha(campo(dados, 'forma'), CHAVES_FORMA_COBRANCA, 'Forma de cobrança');

    await comoDono((bd) =>
      bd.consultar('select definir_forma_cobranca($1::uuid, $2::forma_cobranca)', [assinaturaId, forma]),
    );

    atualizarTelas(undefined, assinaturaId);
    return forma === 'cartao'
      ? 'Forma de cobrança: cartão. Não há integração com operadora: registre cada pagamento quando ele for confirmado.'
      : 'Forma de cobrança: PIX (cobrança mensal manual).';
  });
}

/** Cria a fatura do próximo período agora, sem esperar a rotina diária. */
export async function gerarProximaCobranca(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');

    const fatura = await comoDono(async (bd) => {
      const linha = await bd.umaLinha<{ id: string }>('select gerar_cobranca($1::uuid) as id', [assinaturaId]);
      return bd.umaLinha<{ valor_centavos: number; periodo_inicio: string; periodo_fim: string }>(
        'select valor_centavos, periodo_inicio::text, periodo_fim::text from faturas where id = $1',
        [linha?.id],
      );
    });
    if (!fatura) throw new ErroNegocio('A cobrança não foi criada.');

    atualizarTelas(undefined, assinaturaId);
    return `Cobrança de ${formatarData(fatura.periodo_inicio)} a ${formatarData(fatura.periodo_fim)} criada.`;
  });
}

const RESPOSTAS = ['atendida', 'recusada'] as const;

/** O dono responde ao pedido de pausa/cancelamento; "executar" já pausa ou cancela na mesma transação. */
export async function responderSolicitacao(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const solicitacaoId = uuid(campo(dados, 'solicitacao_id'), 'Pedido');
    const resposta = escolha(campo(dados, 'resposta'), RESPOSTAS, 'Resposta');
    const texto = textoOpcional(campo(dados, 'texto'), 'Mensagem', 500);
    const executar = dados.get('executar') === 'on';
    const retorno = dataOpcional(campo(dados, 'retorno_previsto'), 'Retorno previsto');

    const alvo = await comoDono(async (bd) => {
      await bd.consultar(
        'select resolver_solicitacao($1::uuid, $2::status_solicitacao, $3::text, $4::boolean, $5::date)',
        [solicitacaoId, resposta, texto, executar, retorno],
      );
      return bd.umaLinha<{ assinatura_id: string; cliente_id: string }>(
        'select assinatura_id, cliente_id from solicitacoes_assinatura where id = $1',
        [solicitacaoId],
      );
    });

    if (alvo) atualizarTudo(alvo.cliente_id, alvo.assinatura_id);
    if (resposta === 'recusada') return 'Pedido recusado.';
    return executar ? 'Pedido atendido e executado.' : 'Pedido marcado como atendido.';
  });
}
