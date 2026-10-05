'use server';

import { revalidatePath } from 'next/cache';
import type { Executor } from '@ovo/database';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { campo, cepOpcional, textoOpcional, idNumerico } from '@/lib/validacao';

/**
 * Faixas de CEP atendidas. Quando uma faixa muda, o CEP de todos os clientes
 * é reavaliado: `dentro_area_entrega` é calculado pelo banco (gatilho) a
 * partir do CEP, então basta "regravar" o próprio CEP para que ele recalcule.
 * Sem isso, cadastrar uma faixa não mudaria os clientes que já existem.
 */

function lerFaixa(dados: FormData) {
  const inicio = cepOpcional(campo(dados, 'cep_inicio'));
  const fim = cepOpcional(campo(dados, 'cep_fim'));
  if (!inicio || !fim) throw new ErroNegocio('Informe o CEP inicial e o CEP final.');
  if (fim < inicio) throw new ErroNegocio('O CEP final não pode ser menor que o inicial.');
  return { inicio, fim, bairro: textoOpcional(campo(dados, 'bairro'), 'Bairro', 100) };
}

async function recalcularClientes(bd: Executor): Promise<number> {
  const linhas = await bd.consultar<{ id: string }>(
    'update clientes set cep = cep where cep is not null returning id',
  );
  return linhas.length;
}

export async function criarFaixa(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const f = lerFaixa(dados);
    const n = await comoDono(async (bd) => {
      await bd.consultar(
        'insert into faixas_cep_atendidas (cep_inicio, cep_fim, bairro) values ($1, $2, $3)',
        [f.inicio, f.fim, f.bairro],
      );
      return recalcularClientes(bd);
    });
    revalidatePath('/area-de-entrega');
    revalidatePath('/clientes');
    return `Faixa adicionada. ${n} cliente(s) com CEP reavaliado(s).`;
  });
}

export async function editarFaixa(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Faixa');
    const f = lerFaixa(dados);
    const n = await comoDono(async (bd) => {
      const alterada = await bd.consultar(
        `update faixas_cep_atendidas set cep_inicio = $2, cep_fim = $3, bairro = $4
          where id = $1 returning id`,
        [id, f.inicio, f.fim, f.bairro],
      );
      if (alterada.length === 0) throw new ErroNegocio('Faixa não encontrada.');
      return recalcularClientes(bd);
    });
    revalidatePath('/area-de-entrega');
    revalidatePath('/clientes');
    return `Faixa salva. ${n} cliente(s) com CEP reavaliado(s).`;
  });
}

export async function alternarFaixa(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Faixa');
    const ativar = campo(dados, 'ativar') === 'sim';
    await comoDono(async (bd) => {
      const alterada = await bd.consultar(
        'update faixas_cep_atendidas set ativo = $2 where id = $1 returning id',
        [id, ativar],
      );
      if (alterada.length === 0) throw new ErroNegocio('Faixa não encontrada.');
      await recalcularClientes(bd);
    });
    revalidatePath('/area-de-entrega');
    revalidatePath('/clientes');
    return ativar ? 'Faixa ativada.' : 'Faixa desativada.';
  });
}

export async function removerFaixa(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Faixa');
    await comoDono(async (bd) => {
      const removida = await bd.consultar(
        'delete from faixas_cep_atendidas where id = $1 returning id',
        [id],
      );
      if (removida.length === 0) throw new ErroNegocio('Faixa não encontrada.');
      await recalcularClientes(bd);
    });
    revalidatePath('/area-de-entrega');
    revalidatePath('/clientes');
    return 'Faixa removida.';
  });
}
