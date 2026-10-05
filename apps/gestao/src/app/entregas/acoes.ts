'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { formatarData } from '@/lib/formatar';
import { campo, dataObrigatoria, dataOpcional, escolha, inteiro, textoObrigatorio, textoOpcional, uuid } from '@/lib/validacao';

const SITUACOES = ['entregue', 'nao_entregue', 'cancelada'] as const;

function atualizarTelas(assinaturaId?: string) {
  revalidatePath('/entregas');
  revalidatePath('/');
  revalidatePath('/assinaturas');
  if (assinaturaId) revalidatePath(`/assinaturas/${assinaturaId}`);
}

export async function marcarEntrega(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const entregaId = uuid(campo(dados, 'entrega_id'), 'Entrega');
    const situacao = escolha(campo(dados, 'situacao'), SITUACOES, 'Situação');
    const observacao = textoOpcional(campo(dados, 'observacao'), 'Observação', 500);
    const reagendar = dataOpcional(campo(dados, 'reagendar'), 'Data do reagendamento');

    const resultado = await comoDono(async (bd) => {
      await bd.consultar('select marcar_entrega($1::uuid, $2::status_entrega, $3::text, $4::date)', [
        entregaId,
        situacao,
        observacao,
        reagendar,
      ]);
      return bd.umaLinha<{ assinatura_id: string; proxima: string | null }>(
        `select e.assinatura_id, a.proxima_entrega::text as proxima
           from entregas e join assinaturas a on a.id = e.assinatura_id
          where e.id = $1`,
        [entregaId],
      );
    });

    atualizarTelas(resultado?.assinatura_id);

    const proxima = resultado?.proxima ? ` Próxima entrega: ${formatarData(resultado.proxima)}.` : '';
    if (situacao === 'entregue') return `Entrega marcada como entregue.${proxima}`;
    if (situacao === 'nao_entregue') {
      return reagendar
        ? `Entrega marcada como não entregue e reagendada para ${formatarData(reagendar)}.`
        : 'Entrega marcada como não entregue. Sem nova data: agende uma entrega na assinatura.';
    }
    return `Entrega cancelada.${proxima}`;
  });
}

export async function agendarEntrega(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const data = dataObrigatoria(campo(dados, 'data'), 'Data da entrega');

    await comoDono((bd) =>
      bd.consultar('select agendar_entrega($1::uuid, $2::date)', [assinaturaId, data]),
    );

    atualizarTelas(assinaturaId);
    return `Entrega agendada para ${formatarData(data)}.`;
  });
}

export async function salvarObservacaoEntrega(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const entregaId = uuid(campo(dados, 'entrega_id'), 'Entrega');
    const observacao = textoOpcional(campo(dados, 'observacao'), 'Observação', 500);

    await comoDono((bd) =>
      bd.consultar('select observacao_entrega($1::uuid, $2::text)', [entregaId, observacao]),
    );

    atualizarTelas();
    return 'Observação salva.';
  });
}

/** Horário combinado (opcional). Vazio = sem horário. */
export async function definirHorarioEntrega(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const entregaId = uuid(campo(dados, 'entrega_id'), 'Entrega');
    const bruto = campo(dados, 'horario');
    if (bruto && !/^([01]\d|2[0-3]):[0-5]\d$/.test(bruto)) throw new ErroNegocio('Horário inválido. Use HH:MM.');

    const e = await comoDono(async (bd) => {
      await bd.consultar('select definir_horario_entrega($1::uuid, $2::time)', [entregaId, bruto || null]);
      return bd.umaLinha<{ assinatura_id: string }>('select assinatura_id from entregas where id = $1', [entregaId]);
    });

    atualizarTelas(e?.assinatura_id);
    return bruto ? `Horário definido: ${bruto}.` : 'Horário removido.';
  });
}

/** Ovos com defeito numa entrega feita: a reposição vai na próxima entrega, sem custo. */
export async function registrarDefeito(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const entregaId = uuid(campo(dados, 'entrega_id'), 'Entrega');
    const quantidade = inteiro(campo(dados, 'quantidade'), 'Ovos com defeito', 1, 1500);
    const descricao = textoObrigatorio(campo(dados, 'descricao'), 'Descrição do defeito', 500);

    const r = await comoDono(async (bd) => {
      const linha = await bd.umaLinha<{ id: string }>(
        'select registrar_defeito($1::uuid, $2::smallint, $3::text) as id',
        [entregaId, quantidade, descricao],
      );
      return bd.umaLinha<{ assinatura_id: string; reposicao: string | null }>(
        `select r.assinatura_id, e.data_prevista::text as reposicao
           from reposicoes r left join entregas e on e.id = r.entrega_reposicao_id
          where r.id = $1`,
        [linha?.id],
      );
    });

    atualizarTelas(r?.assinatura_id);
    return r?.reposicao
      ? `Defeito registrado. A reposição vai na entrega de ${formatarData(r.reposicao)}.`
      : 'Defeito registrado. A reposição será ligada à próxima entrega que for agendada.';
  });
}

export async function cancelarReposicao(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const reposicaoId = uuid(campo(dados, 'reposicao_id'), 'Reposição');
    const motivo = textoOpcional(campo(dados, 'motivo'), 'Motivo', 300);

    const r = await comoDono(async (bd) => {
      await bd.consultar('select cancelar_reposicao($1::uuid, $2::text)', [reposicaoId, motivo]);
      return bd.umaLinha<{ assinatura_id: string }>('select assinatura_id from reposicoes where id = $1', [reposicaoId]);
    });

    atualizarTelas(r?.assinatura_id);
    return 'Reposição cancelada.';
  });
}
