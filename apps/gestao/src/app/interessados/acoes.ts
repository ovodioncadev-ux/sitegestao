'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { campo, idNumerico } from '@/lib/validacao';

/**
 * Interessados (quem pediu aviso para um CEP fora da área). Dado pessoal: aqui o
 * dono só muda a situação ou APAGA (pedido de exclusão do titular). Esta tabela
 * não tem auditoria de propósito: a auditoria é imutável e guardaria telefone e
 * e-mail onde não dá para apagar.
 */

function atualizarTelas() {
  revalidatePath('/interessados');
  revalidatePath('/');
}

export async function marcarAvisado(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Interessado');
    const alterado = await comoDono((bd) =>
      bd.consultar(
        `update interessados set status = 'avisado', avisado_em = now(), atualizado_em = now()
          where id = $1 returning id`,
        [id],
      ),
    );
    if (alterado.length === 0) throw new ErroNegocio('Interessado não encontrado.');
    atualizarTelas();
    return 'Marcado como avisado.';
  });
}

export async function descartarInteressado(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Interessado');
    const alterado = await comoDono((bd) =>
      bd.consultar(
        `update interessados set status = 'descartado', atualizado_em = now() where id = $1 returning id`,
        [id],
      ),
    );
    if (alterado.length === 0) throw new ErroNegocio('Interessado não encontrado.');
    atualizarTelas();
    return 'Descartado.';
  });
}

export async function removerInteressado(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Interessado');
    const removido = await comoDono((bd) => bd.consultar('delete from interessados where id = $1 returning id', [id]));
    if (removido.length === 0) throw new ErroNegocio('Interessado não encontrado.');
    atualizarTelas();
    return 'Dados removidos de vez.';
  });
}
