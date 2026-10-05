'use server';

import { revalidatePath } from 'next/cache';
import { buscarCliente, comoAssinante } from '@/lib/assinante';
import { ErroNegocio, rodar } from '@/lib/erros';
import type { Estado } from '@/lib/tipos';
import {
  campo,
  cepObrigatorio,
  escolha,
  telefoneObrigatorio,
  textoObrigatorio,
  textoOpcional,
  ufObrigatoria,
} from '@/lib/validacao';

/**
 * Nada de `update(formData)`: o assinante só grava por duas funções do banco
 * (`atualizar_meus_dados` e `solicitar_alteracao_assinatura`), cada uma com
 * lista fechada de campos e posse conferida na primeira instrução.
 *
 * Por isso NÃO existe aqui como mudar status, plano, preço, e-mail, vínculo de
 * conta ou papel — nem editando o HTML. O id do cliente e o da assinatura
 * nunca vêm do formulário: são derivados da sessão.
 */

export async function atualizarMeusDados(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    // Sem fallback: campo vazio bloqueia o envio.
    const nome = textoObrigatorio(campo(dados, 'nome'), 'Nome', 3, 120);
    const telefone = telefoneObrigatorio(campo(dados, 'telefone'));
    const cep = cepObrigatorio(campo(dados, 'cep'));
    const endereco = textoObrigatorio(campo(dados, 'endereco'), 'Rua', 2, 200);
    const numero = textoObrigatorio(campo(dados, 'numero'), 'Número', 1, 20);
    const complemento = textoOpcional(campo(dados, 'complemento'), 'Complemento', 100);
    const bairro = textoObrigatorio(campo(dados, 'bairro'), 'Bairro', 2, 100);
    const cidade = textoObrigatorio(campo(dados, 'cidade'), 'Cidade', 2, 100);
    const estado = ufObrigatoria(campo(dados, 'estado'));

    await comoAssinante(async (bd, usuarioId) => {
      const cliente = await buscarCliente(bd, usuarioId);
      if (!cliente) throw new ErroNegocio('Sua conta ainda não está ligada a um cadastro.');

      await bd.consultar(
        `select atualizar_meus_dados(
           p_cliente_id  => $1,
           p_nome        => $2,
           p_telefone    => $3,
           p_cep         => $4,
           p_endereco    => $5,
           p_numero      => $6,
           p_complemento => $7,
           p_bairro      => $8,
           p_cidade      => $9,
           p_estado      => $10
         )`,
        [cliente.id, nome, telefone, cep, endereco, numero, complemento, bairro, cidade, estado],
      );
    });

    revalidatePath('/');
    revalidatePath('/dados');
    return 'Dados atualizados.';
  });
}

/**
 * O assinante PEDE pausa ou cancelamento; quem executa é o dono. Assim uma
 * conta comprometida não consegue cancelar um contrato sozinha.
 */
export async function solicitarAlteracao(_estado: Estado, dados: FormData): Promise<Estado> {
  return rodar(async () => {
    const tipo = escolha(campo(dados, 'tipo'), ['pausa', 'cancelamento'] as const, 'Tipo de pedido');
    const motivo = textoOpcional(campo(dados, 'motivo'), 'Motivo', 500);

    await comoAssinante(async (bd, usuarioId) => {
      const cliente = await buscarCliente(bd, usuarioId);
      if (!cliente) throw new ErroNegocio('Sua conta ainda não está ligada a um cadastro.');

      const assinatura = await bd.umaLinha<{ id: string }>(
        `select id from assinaturas
          where cliente_id = $1 and status in ('ativa', 'pausada')
          limit 1`,
        [cliente.id],
      );
      if (!assinatura) throw new ErroNegocio('Você não tem uma assinatura em andamento.');

      await bd.consultar('select solicitar_alteracao_assinatura($1, $2::tipo_solicitacao, $3)', [
        assinatura.id,
        tipo,
        motivo,
      ]);
    });

    revalidatePath('/');
    return tipo === 'pausa'
      ? 'Pedido de pausa enviado. Vamos te responder pelo WhatsApp.'
      : 'Pedido de cancelamento enviado. Vamos te responder pelo WhatsApp.';
  });
}
