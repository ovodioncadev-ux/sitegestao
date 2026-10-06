'use server';

import { revalidatePath } from 'next/cache';
import { comoDono } from '@/lib/dono';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import { campo, idNumerico, inteiro, textoObrigatorio } from '@/lib/validacao';

/**
 * Perguntas frequentes do site. Lista fechada de campos (pergunta, resposta,
 * ordem, ativo); a auditoria registra antes/depois. O telefone do WhatsApp
 * NÃO se escreve aqui: ele vem do código (fonte única, D12).
 */

function lerItem(dados: FormData) {
  const pergunta = textoObrigatorio(campo(dados, 'pergunta'), 'Pergunta', 200);
  const resposta = textoObrigatorio(campo(dados, 'resposta'), 'Resposta', 1000);
  if (pergunta.length < 5) throw new ErroNegocio('A pergunta precisa ter ao menos 5 caracteres.');
  if (resposta.length < 5) throw new ErroNegocio('A resposta precisa ter ao menos 5 caracteres.');
  const ordem = inteiro(campo(dados, 'ordem') || '0', 'Ordem', 0, 9999);
  return { pergunta, resposta, ordem };
}

function atualizarTelas() {
  revalidatePath('/faq');
}

export async function criarPergunta(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const f = lerItem(dados);
    await comoDono((bd) =>
      bd.consultar('insert into faq_itens (pergunta, resposta, ordem) values ($1, $2, $3)', [
        f.pergunta,
        f.resposta,
        f.ordem,
      ]),
    );
    atualizarTelas();
    return 'Pergunta adicionada. Aparece no site em até 30 segundos.';
  });
}

export async function editarPergunta(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Pergunta');
    const f = lerItem(dados);
    const alterada = await comoDono((bd) =>
      bd.consultar(
        `update faq_itens
            set pergunta = $2, resposta = $3, ordem = $4, atualizado_em = now()
          where id = $1
          returning id`,
        [id, f.pergunta, f.resposta, f.ordem],
      ),
    );
    if (alterada.length === 0) throw new ErroNegocio('Pergunta não encontrada.');
    atualizarTelas();
    return 'Pergunta salva. Aparece no site em até 30 segundos.';
  });
}

export async function alternarPergunta(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Pergunta');
    const ativar = campo(dados, 'ativar') === 'sim';
    const alterada = await comoDono((bd) =>
      bd.consultar('update faq_itens set ativo = $2, atualizado_em = now() where id = $1 returning id', [id, ativar]),
    );
    if (alterada.length === 0) throw new ErroNegocio('Pergunta não encontrada.');
    atualizarTelas();
    return ativar ? 'Pergunta publicada.' : 'Pergunta oculta do site.';
  });
}

export async function removerPergunta(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const id = idNumerico(campo(dados, 'id'), 'Pergunta');
    const removida = await comoDono((bd) => bd.consultar('delete from faq_itens where id = $1 returning id', [id]));
    if (removida.length === 0) throw new ErroNegocio('Pergunta não encontrada.');
    atualizarTelas();
    return 'Pergunta removida (fica no histórico).';
  });
}
