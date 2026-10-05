'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { formatarReais } from '@/lib/formatar';
import { CHAVES_METODO } from '@/lib/rotulos';
import {
  campo,
  dataObrigatoria,
  escolha,
  reaisParaCentavos,
  textoOpcional,
  uuid,
} from '@/lib/validacao';

function atualizarTelas(assinaturaId?: string) {
  revalidatePath('/faturas');
  revalidatePath('/');
  if (assinaturaId) revalidatePath(`/assinaturas/${assinaturaId}`);
}

export async function criarFatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const assinaturaId = uuid(campo(dados, 'assinatura_id'), 'Assinatura');
    const vencimento = dataObrigatoria(campo(dados, 'vencimento'), 'Vencimento');
    // Valor em branco = o banco calcula. Preenchido = o dono ajustou.
    const bruto = campo(dados, 'valor');
    const valor = bruto ? reaisParaCentavos(bruto, 'Valor') : null;
    const observacao = textoOpcional(campo(dados, 'observacao'), 'Observação', 500);

    const criada = await comoDono(async (bd) => {
      const linha = await bd.umaLinha<{ id: string }>(
        'select criar_fatura($1::uuid, $2::date, $3::integer, $4::text) as id',
        [assinaturaId, vencimento, valor, observacao],
      );
      return bd.umaLinha<{ valor_centavos: number }>(
        'select valor_centavos from faturas where id = $1',
        [linha?.id],
      );
    });

    atualizarTelas(assinaturaId);
    return `Fatura criada: ${formatarReais(criada?.valor_centavos)}.`;
  });
}

export async function registrarPagamento(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const faturaId = uuid(campo(dados, 'fatura_id'), 'Fatura');
    const data = dataObrigatoria(campo(dados, 'data_pagamento'), 'Data do pagamento');
    const metodo = escolha(campo(dados, 'metodo'), CHAVES_METODO, 'Método de pagamento');
    const observacao = textoOpcional(campo(dados, 'observacao'), 'Observação', 500);

    const fatura = await comoDono(async (bd) => {
      await bd.consultar('select registrar_pagamento($1::uuid, $2::date, $3::metodo_pagamento, $4::text)', [
        faturaId,
        data,
        metodo,
        observacao,
      ]);
      return bd.umaLinha<{ assinatura_id: string }>('select assinatura_id from faturas where id = $1', [
        faturaId,
      ]);
    });

    atualizarTelas(fatura?.assinatura_id);
    revalidatePath('/clientes');
    return 'Pagamento registrado.';
  });
}

export async function cancelarFatura(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const faturaId = uuid(campo(dados, 'fatura_id'), 'Fatura');
    const motivo = textoOpcional(campo(dados, 'motivo'), 'Motivo', 300);

    const fatura = await comoDono(async (bd) => {
      await bd.consultar('select cancelar_fatura($1::uuid, $2::text)', [faturaId, motivo]);
      return bd.umaLinha<{ assinatura_id: string }>('select assinatura_id from faturas where id = $1', [
        faturaId,
      ]);
    });

    atualizarTelas(fatura?.assinatura_id);
    return 'Fatura cancelada.';
  });
}
